const std = @import("std");
const macho = @import("macho.zig");
const fat = @import("fat.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const macho_runtime = @import("macho_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const macho_metadata = @import("metadata.zig");

const log = std.log.scoped(.macho);

const Regs = x64_decoder.Regs;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;

const STACK_SIZE: u64 = 8 * 1024 * 1024;
const MEM_SIZE: u64 = 512 * 1024 * 1024;
const MEM_BASE: u64 = 0x0;
const PAGE_SIZE: u64 = 4096;
const TRACE_BUFFER_LEN: usize = 256;
const IMPORT_TRACE_BUFFER_LEN: usize = 64;
const STUB_ENTRY_SIZE: u64 = 10;
const UNSUPPORTED_RUNTIME_EXIT_CODE: u64 = 125;
const GUEST_FILE_BASE: u64 = 0xFFFF_FF10_0000_0000;
const GUEST_FILE_MAX: usize = 32;

const MachSegment = macho.MachSegment;

const TraceEntry = struct {
    rip: u64 = 0,
    op: Op = .invalid,
    len: u8 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
};

const ImportTraceEntry = struct {
    symbol: []const u8 = "",
    dylib: []const u8 = "",
    stub_address: u64 = 0,
    return_address: u64 = 0,
    synthetic_result: u64 = 0,
    caller_symbol: []const u8 = "",
    caller_offset: u64 = 0,
};

const ImportHandlerResult = union(enum) {
    handled: u64,
    unsupported: u64,
    terminated: u64,
};

const GuestFileKind = enum {
    regular,
    stdout,
    stderr,
};

const GuestFile = struct {
    active: bool = false,
    fd: i32 = -1,
    position: i64 = 0,
    error_flag: bool = false,
    kind: GuestFileKind = .regular,
};

pub const MachOState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    regs: Regs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: u8 = @intFromEnum(exit_diagnostics.TerminationReason.unknown),
    data: []const u8,
    segments: []const MachSegment,
    metadata: macho_metadata.Metadata,
    entry_point_vaddr: u64 = 0,
    stack_size: u64 = 0,
    guest_fds: [16]i32 = .{0} ** 16,
    next_guest_fd: u64 = 3,
    trace_entries: [TRACE_BUFFER_LEN]TraceEntry = [_]TraceEntry{TraceEntry{}} ** TRACE_BUFFER_LEN,
    trace_index: usize = 0,
    trace_filled: bool = false,
    trace_range_start: ?u64 = null,
    trace_range_end: ?u64 = null,
    pending_stub_slot: ?u32 = null,
    pending_stub_entry_rip: ?u64 = null,
    pending_import_stub_rip: ?u64 = null,
    helper_cluster_start: ?u64 = null,
    helper_cluster_end: ?u64 = null,
    import_trace_entries: [IMPORT_TRACE_BUFFER_LEN]ImportTraceEntry = [_]ImportTraceEntry{ImportTraceEntry{}} ** IMPORT_TRACE_BUFFER_LEN,
    import_trace_index: usize = 0,
    import_trace_filled: bool = false,
    unresolved_import_count: u64 = 0,
    guest_files: [GUEST_FILE_MAX]GuestFile = [_]GuestFile{GuestFile{}} ** GUEST_FILE_MAX,

    pub fn init(allocator: std.mem.Allocator, binary_data: []const u8) !MachOState {
        var state = try macho.load(allocator, binary_data);
        errdefer state.deinit();
        var metadata = try macho_metadata.Metadata.init(allocator, binary_data);
        errdefer metadata.deinit();

        var min_vaddr: u64 = std.math.maxInt(u64);
        var max_vaddr: u64 = 0;

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            if (seg.vmaddr < min_vaddr) min_vaddr = seg.vmaddr;
            const seg_end = try std.math.add(u64, seg.vmaddr, seg.vmsize);
            if (seg_end > max_vaddr) max_vaddr = seg_end;
        }

        if (min_vaddr == std.math.maxInt(u64)) return error.NoLoadableSegments;

        const image_base = alignDown(min_vaddr, PAGE_SIZE);
        const image_end = alignUp(max_vaddr, PAGE_SIZE) catch return error.SegmentOverflow;
        const image_size = image_end - image_base;

        const required_mem = image_size + STACK_SIZE;
        const mem_size_aligned = alignUp(required_mem, PAGE_SIZE) catch MEM_SIZE;
        const final_mem_size = @max(mem_size_aligned, MEM_SIZE);

        const mem = try allocator.alloc(u8, @intCast(final_mem_size));
        @memset(mem, 0);

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            const off = (seg.vmaddr -| image_base);
            if (off + seg.vmsize > final_mem_size) continue;
            const copy_size = @min(seg.filesize, seg.vmsize);
            if (copy_size > 0) {
                const file_off = seg.fileoff;
                if (file_off + copy_size <= binary_data.len) {
                    @memcpy(mem[off..][0..@as(usize, @intCast(copy_size))], binary_data[file_off..][0..@as(usize, @intCast(copy_size))]);
                }
            }
        }

        var entry_vaddr: u64 = state.entry_point;
        if (state.entry_point > 0) {
            var mapped_entry: ?u64 = null;
            for (state.segments) |seg| {
                const file_range_end = seg.fileoff + seg.filesize;
                if (state.entry_point >= seg.fileoff and state.entry_point < file_range_end) {
                    mapped_entry = seg.vmaddr + (state.entry_point - seg.fileoff);
                    break;
                }
            }
            if (mapped_entry) |resolved| {
                entry_vaddr = resolved;
            } else if (state.entry_point < image_size) {
                entry_vaddr = image_base + state.entry_point;
            }
        }

        var result = MachOState{
            .allocator = allocator,
            .mem = mem,
            .mem_base = image_base,
            .mem_size = final_mem_size,
            .data = binary_data,
            .segments = try allocator.dupe(MachSegment, state.segments),
            .metadata = metadata,
            .entry_point_vaddr = entry_vaddr,
            .stack_size = if (state.stack_size > 0) state.stack_size else STACK_SIZE,
        };
        result.guest_files[0] = .{ .active = true, .fd = 0, .kind = .regular };
        result.guest_files[1] = .{ .active = true, .fd = 1, .kind = .stdout };
        result.guest_files[2] = .{ .active = true, .fd = 2, .kind = .stderr };
        return result;
    }

    pub fn deinit(self: *MachOState) void {
        self.closeGuestFiles();
        self.metadata.deinit();
        self.allocator.free(self.mem);
        self.allocator.free(self.segments);
    }

    pub fn addrToOffset(self: *const MachOState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    pub fn read8(self: *const MachOState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const MachOState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const MachOState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const MachOState, vaddr: u64) u64 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 8 > self.mem.len) return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
    }

    pub fn write8(self: *MachOState, vaddr: u64, val: u8) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off < self.mem.len) self.mem[off] = val;
    }

    pub fn write16(self: *MachOState, vaddr: u64, val: u16) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 2 <= self.mem.len) std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
    }

    pub fn write32(self: *MachOState, vaddr: u64, val: u32) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 4 <= self.mem.len) std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
    }

    pub fn write64(self: *MachOState, vaddr: u64, val: u64) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 8 <= self.mem.len) std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
    }

    pub fn push(self: *MachOState, val: u64) void {
        self.regs.rsp -|= 8;
        self.write64(self.regs.rsp, val);
    }

    pub fn pop(self: *MachOState) u64 {
        const val = self.read64(self.regs.rsp);
        self.regs.rsp +|= 8;
        return val;
    }

    pub fn readMemVal(self: *MachOState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    pub fn writeMemVal(self: *MachOState, addr: u64, size: Size, val: u64) void {
        switch (size) {
            .bits8 => self.write8(addr, @intCast(val & 0xFF)),
            .bits16 => self.write16(addr, @intCast(val & 0xFFFF)),
            .bits32 => self.write32(addr, @intCast(val & 0xFFFFFFFF)),
            .bits64 => self.write64(addr, val),
        }
    }

    pub fn readMem128(self: *const MachOState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        const off = self.addrToOffset(addr) orelse return value;
        if (off + 16 > self.mem.len) return value;
        @memcpy(value[0..], self.mem[off..][0..16]);
        return value;
    }

    pub fn writeMem128(self: *MachOState, addr: u64, value: [16]u8) void {
        const off = self.addrToOffset(addr) orelse return;
        if (off + 16 > self.mem.len) return;
        @memcpy(self.mem[off..][0..16], value[0..]);
    }

    pub fn guestMemory(self: *MachOState, addr: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn guestMemoryConst(self: *const MachOState, addr: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    fn guestCString(self: *const MachOState, addr: u64, max_len: usize) ?[]const u8 {
        if (addr == 0) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        if (off_usize >= self.mem.len) return null;
        const available = self.mem[off_usize..@min(self.mem.len, off_usize + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..end];
    }

    fn guestWriteCString(self: *MachOState, addr: u64, bytes: []const u8) bool {
        if (self.guestMemory(addr, bytes.len + 1)) |buf| {
            @memcpy(buf[0..bytes.len], bytes);
            buf[bytes.len] = 0;
            return true;
        }
        return false;
    }

    fn allocGuestFile(self: *MachOState, fd: i32, kind: GuestFileKind) ?u64 {
        for (&self.guest_files, 0..) |*file, idx| {
            if (!file.active) {
                file.* = .{
                    .active = true,
                    .fd = fd,
                    .position = 0,
                    .error_flag = false,
                    .kind = kind,
                };
                return GUEST_FILE_BASE + idx;
            }
        }
        return null;
    }

    fn guestFileFromHandle(self: *MachOState, handle: u64) ?*GuestFile {
        if (handle < GUEST_FILE_BASE) return null;
        const idx_u64 = handle - GUEST_FILE_BASE;
        if (idx_u64 >= GUEST_FILE_MAX) return null;
        const idx: usize = @intCast(idx_u64);
        const file = &self.guest_files[idx];
        if (!file.active) return null;
        return file;
    }

    fn closeGuestFiles(self: *MachOState) void {
        for (&self.guest_files) |*file| {
            if (!file.active) continue;
            if (file.kind == .regular and file.fd >= 0) {
                _ = std.c.close(file.fd);
            }
            file.* = .{};
        }
    }

    fn fileOffsetForVaddr(self: *const MachOState, vaddr: u64) ?u64 {
        for (self.segments) |seg| {
            if (vaddr < seg.vmaddr) continue;
            const delta = vaddr - seg.vmaddr;
            if (delta < seg.filesize) {
                return seg.fileoff + delta;
            }
        }
        return null;
    }

    fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
        if (return_addr) |ret_addr| {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} ret=0x{x} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, ret_addr, self.regs.rsp });
        } else {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, self.regs.rsp });
        }
    }

    fn isStubPushJmpEntry(self: *const MachOState, rip: u64) ?struct { slot: u32, target: u64 } {
        const bytes = self.guestMemoryConst(rip, STUB_ENTRY_SIZE) orelse return null;
        if (bytes.len < STUB_ENTRY_SIZE) return null;
        if (bytes[0] != 0x68 or bytes[5] != 0xE9) return null;
        const slot = std.mem.readInt(u32, bytes[1..5], .little);
        const rel = std.mem.readInt(i32, bytes[6..10], .little);
        const target = @as(u64, @bitCast(@as(i64, @as(i64, @intCast(rip + STUB_ENTRY_SIZE)) + rel)));
        return .{ .slot = slot, .target = target };
    }

    fn isSharedStubHelper(self: *const MachOState, rip: u64) bool {
        const bytes = self.guestMemoryConst(rip, 16) orelse return false;
        if (bytes.len < 16) return false;
        return bytes[0] == 0x4C and bytes[1] == 0x8D and bytes[7] == 0x41 and bytes[8] == 0x53 and bytes[9] == 0xFF and bytes[10] == 0x25;
    }

    fn inHelperCluster(self: *const MachOState, rip: u64) bool {
        if (self.helper_cluster_start) |start| {
            const end = self.helper_cluster_end orelse start;
            return rip >= start and rip < end;
        }
        return false;
    }

    fn findSharedHelperCluster(self: *const MachOState, helper_rip: u64) ?struct { start: u64, end: u64 } {
        const helper_bytes = self.guestMemoryConst(helper_rip, 16) orelse return null;
        if (helper_bytes.len < 16) return null;
        var scan = helper_rip;
        var found_start: ?u64 = null;
        var count: usize = 0;
        while (count < 4096) : (count += 1) {
            if (scan < STUB_ENTRY_SIZE) break;
            scan -= STUB_ENTRY_SIZE;
            if (self.isStubPushJmpEntry(scan)) |stub| {
                if (stub.target == helper_rip) {
                    found_start = scan;
                    continue;
                }
            }
            break;
        }
        const start = found_start orelse return null;
        var end = start;
        count = 0;
        while (count < 4096) : (count += 1) {
            if (self.isStubPushJmpEntry(end)) |stub| {
                if (stub.target == helper_rip) {
                    end += STUB_ENTRY_SIZE;
                    continue;
                }
            }
            break;
        }
        return .{ .start = start, .end = end };
    }

    fn dumpGuestStack(self: *const MachOState) void {
        const count: usize = 12;
        std.debug.print("    [stack backtrace (rsp=0x{x}):\n", .{self.regs.rsp});
        var addr = self.regs.rsp;
        for (0..count) |i| {
            const val = self.read64(addr);
            if (val == 0) {
                std.debug.print("      [{d}] 0x{x}: 0x0\n", .{ i, addr });
            } else if (self.metadata.nearestSymbol(val)) |sym| {
                std.debug.print("      [{d}] 0x{x}: 0x{x} → {s}+0x{x}\n", .{ i, addr, val, sym.name, sym.offset });
            } else {
                std.debug.print("      [{d}] 0x{x}: 0x{x}\n", .{ i, addr, val });
            }
            addr +%= 8;
        }
    }

    fn handleStubHelperTransition(self: *MachOState) bool {
        if (self.isStubPushJmpEntry(self.regs.rip)) |stub| {
            self.pending_stub_slot = stub.slot;
            self.pending_stub_entry_rip = self.regs.rip;
            log.info("stub-entry: rip=0x{x} slot=0x{x} shared_helper=0x{x}", .{ self.regs.rip, stub.slot, stub.target });
            self.regs.rip = stub.target;
            return true;
        }

        if (self.pending_stub_slot != null and self.isSharedStubHelper(self.regs.rip)) {
            const slot = self.pending_stub_slot.?;
            const entry_rip = self.pending_stub_entry_rip orelse self.regs.rip;
            const synthetic_return = self.read64(self.regs.rsp);
            if (self.findSharedHelperCluster(self.regs.rip)) |cluster| {
                self.helper_cluster_start = cluster.start;
                self.helper_cluster_end = cluster.end;
                log.info("stub-helper cluster: helper_rip=0x{x} cluster=[0x{x}, 0x{x})", .{ self.regs.rip, cluster.start, cluster.end });
            }
            self.pending_stub_slot = null;
            self.pending_stub_entry_rip = null;
            self.regs.rax = 0;
            if (self.pending_import_stub_rip) |import_stub_rip| {
                if (self.metadata.importAtStub(import_stub_rip)) |imported| {
                    switch (self.handleImport(imported.name)) {
                        .handled => |result| {
                            self.regs.rax = result;
                            std.debug.print("  [handled import] {s} from {s}; stub=0x{x} return=0x{x} → rax=0x{x}\n", .{
                                imported.name,
                                imported.dylib,
                                imported.stub_address,
                                synthetic_return,
                                result,
                            });
                        },
                        .unsupported => |result| {
                            self.regs.rax = result;
                            self.recordUnresolvedImport(imported, synthetic_return, self.regs.rax);
                            if (self.metadata.nearestSymbol(synthetic_return)) |caller_sym| {
                                std.debug.print(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller={s}+0x{x} return=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, caller_sym.name, caller_sym.offset, synthetic_return, self.regs.rax },
                                );
                            } else {
                                std.debug.print(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, synthetic_return, self.regs.rax },
                                );
                            }
                            self.dumpGuestStack();
                        },
                        .terminated => |exit_code| {
                            self.exit_code = exit_code;
                            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                            self.terminated = true;
                            std.debug.print("  [handled terminal import] {s}({d})\n", .{ imported.name, exit_code });
                        },
                    }
                }
            }
            self.pending_import_stub_rip = null;
            if (self.terminated) return true;
            if (synthetic_return != 0 and self.addrToOffset(synthetic_return) != null) {
                log.warn("stub-helper aggressive fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x} synthetic_return=0x{x}; simulating resolved helper return", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                _ = self.pop();
                self.regs.rip = synthetic_return;
            } else {
                log.warn("stub-helper conservative fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x}; synthetic_return invalid (0x{x}), skipping helper entry", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                self.regs.rip = entry_rip + STUB_ENTRY_SIZE;
            }
            return true;
        }

        if (self.inHelperCluster(self.regs.rip)) {
            const cluster_end = self.helper_cluster_end orelse self.regs.rip;
            log.warn("helper-cluster escape: rip=0x{x} cluster_end=0x{x}; forcing exit from packed stub region", .{ self.regs.rip, cluster_end });
            self.regs.rax = 0;
            self.regs.rip = cluster_end;
            self.helper_cluster_start = null;
            self.helper_cluster_end = null;
            return true;
        }

        return false;
    }

    fn handleImport(self: *MachOState, name: []const u8) ImportHandlerResult {
        if (std.mem.eql(u8, name, "_exit") or std.mem.eql(u8, name, "exit")) {
            return .{ .terminated = self.regs.rdi & 0xFF };
        }

        if (std.mem.endsWith(u8, name, "_memset")) {
            const dst = self.regs.rdi;
            const value: u8 = @intCast(self.regs.rsi & 0xFF);
            const count = self.regs.rdx;
            if (self.guestMemory(dst, count)) |buf| {
                @memset(buf, value);
                std.debug.print("    [import] _memset(dst=0x{x}, value=0x{x}, count={d})\n", .{ dst, value, count });
            }
            return .{ .handled = dst };
        }

        if (std.mem.endsWith(u8, name, "_memcpy") or std.mem.endsWith(u8, name, "_memmove")) {
            const dst = self.regs.rdi;
            const src = self.regs.rsi;
            const count = self.regs.rdx;
            const src_buf = self.guestMemoryConst(src, count) orelse return .{ .unsupported = 0 };
            const dst_buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
            std.mem.copyForwards(u8, dst_buf, src_buf);
            return .{ .handled = dst };
        }

        if (std.mem.endsWith(u8, name, "_memcmp")) {
            const lhs = self.guestMemoryConst(self.regs.rdi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const rhs = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const cmp = std.mem.order(u8, lhs, rhs);
            return .{ .handled = switch (cmp) {
                .lt => @bitCast(@as(i64, -1)),
                .eq => 0,
                .gt => 1,
            } };
        }

        if (std.mem.endsWith(u8, name, "_strlen")) {
            const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            return .{ .handled = text.len };
        }

        if (std.mem.endsWith(u8, name, "_time")) {
            const now_i64: i64 = 1_719_000_000;
            const now: u64 = @bitCast(now_i64);
            const out_ptr = self.regs.rdi;
            if (out_ptr != 0) {
                if (self.guestMemory(out_ptr, 8)) |buf| {
                    std.mem.writeInt(u64, buf[0..8], now, .little);
                }
            }
            return .{ .handled = now };
        }

        if (std.mem.endsWith(u8, name, "_fopen")) {
            return .{ .handled = self.handleFopen() orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_fclose")) {
            return .{ .handled = self.handleFclose() };
        }
        if (std.mem.endsWith(u8, name, "_fprintf")) {
            return .{ .handled = self.handleFprintf() };
        }
        if (std.mem.endsWith(u8, name, "_fputs")) {
            return .{ .handled = self.handleFputs() };
        }
        if (std.mem.endsWith(u8, name, "_fflush")) {
            return .{ .handled = self.handleFflush() };
        }
        if (std.mem.endsWith(u8, name, "_ftell")) {
            return .{ .handled = self.handleFtell() };
        }
        if (std.mem.endsWith(u8, name, "_fseek")) {
            return .{ .handled = self.handleFseek() };
        }
        if (std.mem.endsWith(u8, name, "_ferror")) {
            return .{ .handled = self.handleFerror() };
        }
        if (std.mem.endsWith(u8, name, "_printf")) {
            return .{ .handled = self.handlePrintfLike(null) };
        }
        if (std.mem.endsWith(u8, name, "_putchar")) {
            return .{ .handled = self.handlePutchar() };
        }

        if (std.mem.endsWith(u8, name, "_gtk_init_check")) {
            return .{ .handled = self.handleGtkInitCheck() };
        }

        if (std.mem.endsWith(u8, name, "_localtime") or std.mem.endsWith(u8, name, "_strftime")) {
            return .{ .handled = 0 };
        }

        return .{ .unsupported = 0 };
    }

    fn recordUnresolvedImport(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
        synthetic_result: u64,
    ) void {
        var entry = ImportTraceEntry{
            .symbol = imported.name,
            .dylib = imported.dylib,
            .stub_address = imported.stub_address,
            .return_address = return_address,
            .synthetic_result = synthetic_result,
        };
        if (self.metadata.nearestSymbol(return_address)) |caller_sym| {
            entry.caller_symbol = caller_sym.name;
            entry.caller_offset = caller_sym.offset;
        }
        self.import_trace_entries[self.import_trace_index] = entry;
        self.import_trace_index = (self.import_trace_index + 1) % IMPORT_TRACE_BUFFER_LEN;
        if (self.import_trace_index == 0) self.import_trace_filled = true;
        self.unresolved_import_count += 1;
    }

    fn hostWriteAll(self: *MachOState, file: *GuestFile, bytes: []const u8) bool {
        _ = self;
        if (file.fd < 0) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const rc = std.c.write(file.fd, bytes.ptr + written, bytes.len - written);
            if (rc < 0) {
                file.error_flag = true;
                return false;
            }
            if (rc == 0) break;
            written += @intCast(rc);
        }
        if (file.kind == .regular) file.position += @intCast(written);
        return written == bytes.len;
    }

    fn handleFopen(self: *MachOState) ?u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
        const mode = self.guestCString(self.regs.rsi, 32) orelse return null;
        const flags = parseFopenFlags(mode) orelse return null;
        var path_buf = std.ArrayList(u8).empty;
        defer path_buf.deinit(self.allocator);
        path_buf.appendSlice(self.allocator, path) catch return null;
        path_buf.append(self.allocator, 0) catch return null;
        const zpath: [*:0]const u8 = @ptrCast(path_buf.items.ptr);
        const fd = std.c.open(zpath, @bitCast(@as(u32, @intCast(flags))), @as(c_int, 0o666));
        if (fd < 0) return null;
        return self.allocGuestFile(fd, .regular);
    }

    fn handleFclose(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (file.kind == .regular and file.fd >= 0) {
            if (std.c.close(file.fd) != 0) {
                file.error_flag = true;
                return @bitCast(@as(i64, -1));
            }
        }
        file.* = .{};
        return 0;
    }

    fn handleFputs(self: *MachOState) u64 {
        const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return @bitCast(@as(i64, -1));
        const file = self.guestFileFromHandle(self.regs.rsi) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(file, text)) return @bitCast(@as(i64, -1));
        return @intCast(text.len);
    }

    fn handleFflush(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (std.c.fsync(file.fd) != 0 and file.kind == .regular) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
        return 0;
    }

    fn handleFtell(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        return @bitCast(file.position);
    }

    fn handleFseek(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const offset: i64 = @bitCast(self.regs.rsi);
        const whence: i32 = @intCast(self.regs.rdx);
        if (file.fd < 0) return @bitCast(@as(i64, -1));
        const pos = std.c.lseek(file.fd, offset, whence);
        if (pos < 0) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
        file.position = pos;
        return 0;
    }

    fn handleFerror(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return 1;
        return if (file.error_flag) 1 else 0;
    }

    fn handleFprintf(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        return self.handlePrintfLike(file);
    }

    fn handlePrintfLike(self: *MachOState, file_opt: ?*GuestFile) u64 {
        const format = self.guestCString(self.regs.rsi, 1 << 20) orelse return @bitCast(@as(i64, -1));
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var output = std.ArrayList(u8).empty;
        defer output.deinit(allocator);

        var gp_index: usize = 2;
        var stack_arg_addr = self.regs.rsp + 8;
        var i: usize = 0;
        while (i < format.len) : (i += 1) {
            if (format[i] != '%') {
                output.append(allocator, format[i]) catch return @bitCast(@as(i64, -1));
                continue;
            }
            i += 1;
            if (i >= format.len) break;
            if (format[i] == '%') {
                output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                continue;
            }

            while (i < format.len and (format[i] == '-' or format[i] == '+' or format[i] == ' ' or format[i] == '#' or format[i] == '0')) : (i += 1) {}
            while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            if (i < format.len and format[i] == '.') {
                i += 1;
                while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            }
            var long_count: usize = 0;
            while (i < format.len and format[i] == 'l') : (i += 1) long_count += 1;
            if (i >= format.len) break;

            const spec = format[i];
            const arg = self.nextVarArg(&gp_index, &stack_arg_addr);
            switch (spec) {
                's' => {
                    const text = self.guestCString(arg, 1 << 20) orelse "(null)";
                    output.appendSlice(allocator, text) catch return @bitCast(@as(i64, -1));
                },
                'd', 'i' => {
                    const val: i64 = @bitCast(arg);
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{val}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'u' => {
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'x' => {
                    const rendered = std.fmt.allocPrint(allocator, "{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'X' => {
                    const rendered = std.fmt.allocPrint(allocator, "{X}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'p' => {
                    const rendered = std.fmt.allocPrint(allocator, "0x{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'c' => {
                    output.append(allocator, @intCast(arg & 0xFF)) catch return @bitCast(@as(i64, -1));
                },
                'z' => {
                    output.append(allocator, 'z') catch return @bitCast(@as(i64, -1));
                },
                else => {
                    output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                    output.append(allocator, spec) catch return @bitCast(@as(i64, -1));
                },
            }
        }

        const sink = file_opt orelse self.guestFileFromHandle(GUEST_FILE_BASE + 1).?;
        if (!self.hostWriteAll(sink, output.items)) return @bitCast(@as(i64, -1));
        return output.items.len;
    }

    fn handlePutchar(self: *MachOState) u64 {
        const ch: u8 = @intCast(self.regs.rdi & 0xFF);
        const sink = self.guestFileFromHandle(GUEST_FILE_BASE + 1) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(sink, &[_]u8{ch})) return @bitCast(@as(i64, -1));
        return ch;
    }

    fn handleGtkInitCheck(self: *MachOState) u64 {
        const argc_ptr = self.regs.rdi;
        const argv_ptr = self.regs.rsi;
        _ = argc_ptr;
        _ = argv_ptr;
        std.debug.print("    [import] _gtk_init_check compatibility shim → success\n", .{});
        return 1;
    }

    fn nextVarArg(self: *const MachOState, gp_index: *usize, stack_arg_addr: *u64) u64 {
        const regs = [_]u64{ self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
        if (gp_index.* < regs.len) {
            defer gp_index.* += 1;
            return regs[gp_index.*];
        }
        const addr = stack_arg_addr.*;
        stack_arg_addr.* += 8;
        return self.read64(addr);
    }

    fn recordTrace(self: *MachOState, decoded: DecodedInsn) void {
        self.trace_entries[self.trace_index] = .{
            .rip = self.regs.rip,
            .op = decoded.op,
            .len = decoded.len,
            .rsp = self.regs.rsp,
            .rax = self.regs.rax,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
        };
        self.trace_index = (self.trace_index + 1) % TRACE_BUFFER_LEN;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    fn shouldTraceRIP(self: *const MachOState, rip: u64) bool {
        if (self.trace_range_start) |start| {
            const end = self.trace_range_end orelse start;
            return rip >= start and rip <= end;
        }
        return false;
    }

    fn dumpRecentTrace(self: *const MachOState) void {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (count == 0) return;
        log.err("recent trace dump (most recent last, count={d})", .{count});
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = if (self.trace_filled)
                (self.trace_index + i) % TRACE_BUFFER_LEN
            else
                i;
            const entry = self.trace_entries[idx];
            log.err("trace[{d}]: rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                i,
                entry.rip,
                @tagName(entry.op),
                entry.len,
                entry.rsp,
                entry.rax,
                entry.rcx,
                entry.rdx,
            });
        }
    }

    fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn setFlagsSub(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *MachOState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *MachOState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn bitWidth(size: Size) u7 {
        return switch (size) {
            .bits8 => 8,
            .bits16 => 16,
            .bits32 => 32,
            .bits64 => 64,
        };
    }

    fn maskForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    fn signBitForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0x80,
            .bits16 => 0x8000,
            .bits32 => 0x8000_0000,
            .bits64 => 0x8000_0000_0000_0000,
        };
    }

    fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
        const signed: i64 = switch (size) {
            .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
            .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
            .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
            .bits64 => @bitCast(value),
        };
        return @as(u64, @bitCast(signed >> count)) & maskForSize(size);
    }

    fn setupInitialStack(self: *MachOState, args: []const []const u8) void {
        var sp = self.mem_base + self.mem_size;

        sp -= 8;
        self.write64(sp, 0);

        sp -= 8;
        const envp_addr = sp;
        self.write64(sp, 0);

        var arg_addrs: std.ArrayList(u64) = .empty;
        defer arg_addrs.deinit(self.allocator);
        for (args) |arg| {
            sp -|= arg.len + 1;
            for (arg, 0..) |c, i| {
                self.write8(sp + i, c);
            }
            self.write8(sp + arg.len, 0);
            arg_addrs.append(self.allocator, sp) catch {};
        }

        sp -= 8;
        self.write64(sp, 0);

        for (0..arg_addrs.items.len) |i| {
            sp -= 8;
            self.write64(sp, arg_addrs.items[arg_addrs.items.len - 1 - i]);
        }
        const argv_addr = sp;

        sp -= 8;
        const argc_val: u64 = @intCast(args.len);
        self.write64(sp, argc_val);

        sp &= ~@as(u64, 15);
        sp -= 8;

        self.regs.rdi = argc_val;
        self.regs.rsi = argv_addr;
        self.regs.rdx = envp_addr;
        self.regs.rsp = sp;
    }

    fn setupMachOState(self: *MachOState, path: []const u8, args: []const []const u8) void {
        var full_args = std.ArrayList([]const u8).empty;
        defer full_args.deinit(self.allocator);
        full_args.append(self.allocator, path) catch {};
        for (args) |a| full_args.append(self.allocator, a) catch {};

        self.trace_range_start = 0x1332000;
        self.trace_range_end = 0x1333000;
        self.setupInitialStack(full_args.items);
        self.regs.rip = self.entry_point_vaddr;
    }

    fn decodeAt(self: *MachOState) ?DecodedInsn {
        const off = self.addrToOffset(self.regs.rip) orelse return null;
        const bytes = self.mem[off..];
        var d = decodeInsn(bytes);

        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        if (d.sib_has_index) {
            const index_val = self.regVal(d.sib_index_reg, addr_size);
            d.addr +%= index_val << @as(u6, d.sib_scale);
        }
        if (d.sib_has_base) {
            const base_val = self.regVal(d.sib_base_reg, addr_size);
            d.addr +%= base_val;
        }
        if (d.rip_relative) {
            d.addr +%= self.regs.rip + d.len;
        }

        return d;
    }

    fn step(self: *MachOState) bool {
        if (self.handleStubHelperTransition()) {
            return !self.terminated;
        }
        const decoded = self.decodeAt() orelse {
            const rip = self.regs.rip;
            std.debug.print("macho-processor: decode failed at rip=0x{x}\n", .{rip});
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                std.debug.print("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: decode failed at unmapped address\n", .{});
            }
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const mem_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            const rip = self.regs.rip;
            std.debug.print("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=0x{x} file_bytes={any}\n", .{ rip, file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=<unmapped>\n", .{rip});
            }
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
            self.terminated = true;
            return false;
        }
        self.recordTrace(decoded);
        log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
        if (self.shouldTraceRIP(self.regs.rip)) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            log.info("target-trace: rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                self.regs.rsp,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
            });
            log.info("target-trace-bytes: rip=0x{x} bytes={any}", .{ self.regs.rip, trace_bytes });
        }
        const old_rip = self.regs.rip;
        x64_interpreter.execute(self, decoded);
        if (!self.terminated and self.regs.rip == old_rip) {
            self.regs.rip +%= decoded.len;
        }
        return !self.terminated;
    }

    pub fn run(self: *MachOState) void {
        var steps: u64 = 0;
        const max_steps: u64 = 5_000_000;
        while (!self.terminated and steps < max_steps) : (steps += 1) {
            if (steps % 500000 == 0) {
                log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}", .{ steps, self.regs.rip, self.regs.rax, self.regs.rbx, self.regs.rcx });
            }
            if (!self.step()) break;
        }
        if (steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.max_steps_reached);
            self.terminated = true;
        }
        if (self.unresolved_import_count != 0) {
            const current_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
            if (current_reason == .unknown or current_reason == .ret_stack_empty or current_reason == .exit_syscall) {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            }
        }
        if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
            self.logExitDiagnostics();
        }
    }

    fn logExitDiagnostics(self: *const MachOState) void {
        const reason: exit_diagnostics.TerminationReason = exit_diagnostics.reasonFromValue(self.termination_reason);
        var report = exit_diagnostics.ExitReport{
            .exit_code = self.exit_code,
            .reason = reason,
            .faulted = self.faulted,
            .rip = self.regs.rip,
            .regs = .{
                .rax = self.regs.rax,
                .rbx = self.regs.rbx,
                .rcx = self.regs.rcx,
                .rdx = self.regs.rdx,
                .rsi = self.regs.rsi,
                .rdi = self.regs.rdi,
                .rbp = self.regs.rbp,
                .rsp = self.regs.rsp,
                .r8 = self.regs.r8,
                .r9 = self.regs.r9,
                .r10 = self.regs.r10,
                .r11 = self.regs.r11,
                .r12 = self.regs.r12,
                .r13 = self.regs.r13,
                .r14 = self.regs.r14,
                .r15 = self.regs.r15,
            },
            .execution_authoritative = self.unresolved_import_count == 0,
        };

        if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
            report.terminal_symbol = .{
                .address = symbol.address,
                .symbol = symbol.name,
                .symbol_offset = symbol.offset,
            };
        }

        const import_trace_count: usize = if (self.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else self.import_trace_index;
        if (import_trace_count > 0) {
            var import_trace_buf: [IMPORT_TRACE_BUFFER_LEN]exit_diagnostics.DependencyCall = undefined;
            for (0..import_trace_count) |i| {
                const idx = if (self.import_trace_filled)
                    (self.import_trace_index + i) % IMPORT_TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.import_trace_entries[idx];
                import_trace_buf[i] = .{
                    .symbol = entry.symbol,
                    .image = entry.dylib,
                    .stub_address = entry.stub_address,
                    .return_address = entry.return_address,
                    .synthetic_result = entry.synthetic_result,
                    .caller_symbol = entry.caller_symbol,
                    .caller_offset = entry.caller_offset,
                };
            }
            report.dependency_calls = import_trace_buf[0..import_trace_count];
            report.detail = "The interpreter did not execute these dynamic-library functions; the guest exit code is not authoritative.";
        }

        const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (trace_count > 0) {
            var trace_buf: [TRACE_BUFFER_LEN]exit_diagnostics.TraceEntry = undefined;
            for (0..trace_count) |i| {
                const idx = if (self.trace_filled)
                    (self.trace_index + i) % TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.trace_entries[idx];
                trace_buf[i] = .{
                    .rip = entry.rip,
                    .op = @tagName(entry.op),
                    .len = entry.len,
                    .rsp = entry.rsp,
                    .rax = entry.rax,
                    .rcx = entry.rcx,
                    .rdx = entry.rdx,
                };
            }
            report.last_instructions = trace_buf[0..trace_count];
        }

        exit_diagnostics.logExitReport(report);
    }

    pub fn execute(self: *MachOState, d: DecodedInsn) void {
        switch (d.op) {
            .invalid => unreachable,
            .nop => {},

            .mov_reg8_mem8 => {
                self.setReg(d.dst_reg, .bits8, self.readMemVal(d.addr, .bits8));
            },
            .mov_reg16_mem16 => {
                self.setReg(d.dst_reg, .bits16, self.readMemVal(d.addr, .bits16));
            },
            .mov_reg32_mem32 => {
                self.setReg(d.dst_reg, .bits32, self.readMemVal(d.addr, .bits32));
            },
            .mov_reg64_mem64 => {
                self.setReg(d.dst_reg, .bits64, self.readMemVal(d.addr, .bits64));
            },

            .mov_mem8_reg8 => {
                self.writeMemVal(d.addr, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_mem16_reg16 => {
                self.writeMemVal(d.addr, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_mem32_reg32 => {
                self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_mem64_reg64 => {
                self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .mov_reg_imm => {
                self.setReg(d.dst_reg, d.size, d.imm);
            },

            .mov_mem8_imm8 => {
                self.writeMemVal(d.addr, .bits8, d.imm);
            },
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            .mov_reg8_reg8 => {
                self.setReg(d.dst_reg, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_reg16_reg16 => {
                self.setReg(d.dst_reg, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_reg32_reg32 => {
                self.setReg(d.dst_reg, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_reg64_reg64 => {
                self.setReg(d.dst_reg, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a +% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsAdd(a, b, r, sz);
            },
            .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a +% b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsAdd(a, b, r, sz);
            },

            .add_reg8_imm8 => self.executeAddRegImm(d, .bits8),
            .add_reg16_imm8 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm8 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm8 => self.executeAddRegImm(d, .bits64),
            .add_reg16_imm32 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm32 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm32 => self.executeAddRegImm(d, .bits64),

            .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a -% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeSubRegImm(d, sz);
            },
            .sbb_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .sbb_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },

            .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a & b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => self.executeAndRegImm(d),
            .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => self.executeAndRegImm(d),

            .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a | b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a | b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a | b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const r = a | b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
            },

            .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a ^ b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a ^ b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a ^ b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_imm8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a ^ d.imm;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },

            .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_imm8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a -% d.imm;
                self.setFlagsSub(a, d.imm, r, sz);
            },
            .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_imm8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a -% d.imm;
                self.setFlagsSub(a, d.imm, r, sz);
            },

            .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setFlagsLogic(r, sz);
            },
            .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setFlagsLogic(r, sz);
            },
            .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => {
                const r = self.regVal(d.dst_reg, d.size) & d.imm;
                self.setFlagsLogic(r, d.size);
            },
            .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => {
                const r = self.readMemVal(d.addr, d.size) & d.imm;
                self.setFlagsLogic(r, d.size);
            },

            .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a +% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a +% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a -% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },
            .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a -% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },

            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = (~a +% 1) & maskForSize(sz);
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
                self.setFlag(RFL_CF, a != 0);
            },

            .push_reg => {
                self.push(self.regVal(d.dst_reg, .bits64));
            },
            .push_mem64 => {
                self.push(self.readMemVal(d.addr, .bits64));
            },
            .push_imm => {
                self.push(d.imm);
            },

            .pop_reg => {
                self.setReg(d.dst_reg, .bits64, self.pop());
            },
            .pop_mem64 => {
                self.writeMemVal(d.addr, .bits64, self.pop());
            },

            .lods => {
                const src_addr = self.regs.rsi;
                switch (d.size) {
                    .bits8 => self.setReg(.al_ax_eax_rax, .bits8, self.readMemVal(src_addr, .bits8)),
                    .bits16 => self.setReg(.al_ax_eax_rax, .bits16, self.readMemVal(src_addr, .bits16)),
                    .bits32 => self.setReg(.al_ax_eax_rax, .bits32, self.readMemVal(src_addr, .bits32)),
                    .bits64 => self.setReg(.al_ax_eax_rax, .bits64, self.readMemVal(src_addr, .bits64)),
                }
                const stride: u64 = switch (d.size) {
                    .bits8 => 1,
                    .bits16 => 2,
                    .bits32 => 4,
                    .bits64 => 8,
                };
                if ((self.regs.rflags & RFL_DF) != 0) {
                    self.regs.rsi -|= stride;
                } else {
                    self.regs.rsi +|= stride;
                }
            },

            .call_rel32 => {
                const target = d.addr;
                const return_addr = self.regs.rip + d.len;
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_rel32", self.regs.rip - d.len, target, d.len, return_addr);
            },
            .call_reg64 => {
                const from_rip = self.regs.rip;
                const target = self.regVal(d.dst_reg, .bits64);
                const return_addr = self.regs.rip + d.len;
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_reg64", from_rip, target, d.len, return_addr);
            },
            .call_mem64 => {
                const from_rip = self.regs.rip;
                const target = self.readMemVal(d.addr, .bits64);
                const return_addr = self.regs.rip + d.len;
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_mem64", from_rip, target, d.len, return_addr);
            },

            .ret => {
                if (d.imm > 0) {
                    self.regs.rsp +|= d.imm;
                }
                const ret_addr = self.pop();
                if (ret_addr == 0) {
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.ret_stack_empty);
                    self.terminated = true;
                    self.exit_code = self.regs.rax;
                    return;
                }
                self.logControlFlow("ret", self.regs.rip, ret_addr, d.len, null);
                self.regs.rip = ret_addr;
            },

            .jmp_rel8, .jmp_reg64 => {
                self.logControlFlow("jmp", self.regs.rip, d.addr, d.len, null);
                self.regs.rip = d.addr;
            },
            .jmp_mem64 => {
                self.pending_import_stub_rip = if (self.metadata.importAtStub(self.regs.rip) != null) self.regs.rip else null;
                const target = self.readMemVal(d.addr, .bits64);
                self.logControlFlow("jmp_mem64", self.regs.rip, target, d.len, null);
                self.regs.rip = target;
            },

            .jcc_rel8, .jcc_rel32 => {
                const condMet = x64_decoder.evalCond(self.regs.rflags, d.cond);
                if (condMet) {
                    self.logControlFlow("jcc_taken", self.regs.rip, d.addr, d.len, null);
                    self.regs.rip = d.addr;
                }
            },

            .shl_reg_cl, .shl_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_cl, .shr_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_cl, .sar_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_imm, .shr_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shl_reg_imm, .shl_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_imm, .sar_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },

            .mul_reg8 => {
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const b = self.regVal(d.dst_reg, .bits8);
                const r = a * b;
                self.setReg(.al_ax_eax_rax, .bits16, r);
            },
            .mul_reg16 => {
                const a = self.regVal(.al_ax_eax_rax, .bits16);
                const b = self.regVal(d.dst_reg, .bits16);
                const r: u32 = @as(u32, @truncate(a)) * @as(u32, @truncate(b));
                self.setReg(.al_ax_eax_rax, .bits16, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits16, @truncate(r >> 16));
            },
            .mul_reg32 => {
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const b = self.regVal(d.dst_reg, .bits32);
                const r: u64 = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(r >> 32));
            },
            .mul_reg64 => {
                const a = self.regs.rax;
                const b = self.regVal(d.dst_reg, .bits64);
                @setRuntimeSafety(false);
                const r = @as(u128, a) * @as(u128, b);
                self.regs.rax = @truncate(r);
                self.regs.rdx = @truncate(r >> 64);
            },

            .div_reg64 => {
                const divisor = self.regVal(d.dst_reg, .bits64);
                if (divisor == 0) {
                    self.faulted = true;
                    self.terminated = true;
                    self.exit_code = 136;
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.divide_by_zero);
                    return;
                }
                const dividend = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
                self.regs.rax = @truncate(dividend / divisor);
                self.regs.rdx = @truncate(dividend % divisor);
            },

            .imul_reg64_reg64, .imul_reg32_reg32 => {
                const sz = if (d.op == .imul_reg64_reg64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64, .imul_reg32_mem32 => {
                const sz = if (d.op == .imul_reg64_mem64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_reg64_imm8, .imul_reg32_reg32_imm8 => {
                const sz = if (d.op == .imul_reg64_reg64_imm8) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const r = a *% d.imm;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64_imm8, .imul_reg32_mem32_imm8 => {
                const sz = if (d.op == .imul_reg64_mem64_imm8) Size.bits64 else Size.bits32;
                const a = self.readMemVal(d.addr, sz);
                const r = a *% d.imm;
                self.setReg(d.dst_reg, sz, r);
            },

            .lea_reg_mem => {
                self.setReg(d.dst_reg, d.size, d.addr);
            },

            .movzx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movzx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movsx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsxd_reg64_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },
            .movsxd_reg64_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },

            .cbw => {
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(@as(u8, @truncate(self.regs.rax))))))));
            },
            .cwde => {
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(self.regs.rax))))))));
            },
            .cdqe => {
                self.regs.rax = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs.rax)))))));
            },
            .cwd => {
                const val = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = @as(u16, @bitCast(@as(i16, @intCast(val)))) >> 15;
                self.setReg(.dl_dx_edx_rdx, .bits16, if (sign != 0) 0xFFFF else 0);
            },
            .cdq => {
                const val = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = @as(u32, @bitCast(@as(i32, @intCast(val)))) >> 31;
                self.setReg(.dl_dx_edx_rdx, .bits32, if (sign != 0) 0xFFFF_FFFF else 0);
            },
            .cqo => {
                const val = self.regs.rax;
                const sign = (val & 0x8000_0000_0000_0000) != 0;
                self.regs.rdx = if (sign) 0xFFFF_FFFF_FFFF_FFFF else 0;
            },

            .cmovcc_reg_reg => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
                }
            },
            .cmovcc_reg_mem => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
                }
            },

            .setcc_reg8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, .bits8, 1);
                } else {
                    self.setReg(d.dst_reg, .bits8, 0);
                }
            },
            .setcc_mem8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.writeMemVal(d.addr, .bits8, 1);
                } else {
                    self.writeMemVal(d.addr, .bits8, 0);
                }
            },

            .cmpxchg_mem32_reg32 => {
                const expected = self.regVal(.al_ax_eax_rax, .bits32);
                const actual = self.readMemVal(d.addr, .bits32);
                if (expected == actual) {
                    self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.setReg(.al_ax_eax_rax, .bits32, actual);
                    self.setFlag(RFL_ZF, false);
                }
            },
            .cmpxchg_mem64_reg64 => {
                const expected = self.regs.rax;
                const actual = self.readMemVal(d.addr, .bits64);
                if (expected == actual) {
                    self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.regs.rax = actual;
                    self.setFlag(RFL_ZF, false);
                }
            },

            .xchg_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, b);
                self.setReg(d.src_reg, .bits32, a);
            },
            .xchg_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, b);
                self.setReg(d.src_reg, .bits64, a);
            },

            .xorps_xmm_xmm => {
                const dst = d.xmm_dst;
                const src = d.xmm_src;
                for (&self.xmm[dst], self.xmm[src]) |*d8, s8| d8.* = d8.* ^ s8;
            },
            .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            },
            .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_dst]);
            },

            .syscall => {
                self.dispatchMacOSSyscall(
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    self.regs.r10,
                    self.regs.r8,
                    self.regs.r9,
                );
            },

            .cpuid => {
                const leaf: u32 = @truncate(self.regs.rax);
                const subleaf: u32 = @truncate(self.regs.rcx);
                const result = x64_decoder.emulatedCpuid(leaf, subleaf);
                log.info(
                    "cpuid: leaf=0x{x} subleaf=0x{x} -> eax=0x{x} ebx=0x{x} ecx=0x{x} edx=0x{x}",
                    .{ leaf, subleaf, result.eax, result.ebx, result.ecx, result.edx },
                );
                self.setReg(.al_ax_eax_rax, .bits32, result.eax);
                self.setReg(.bl_bx_ebx_rbx, .bits32, result.ebx);
                self.setReg(.cl_cx_ecx_rcx, .bits32, result.ecx);
                self.setReg(.dl_dx_edx_rdx, .bits32, result.edx);
            },

            .xgetbv => {
                const xcr0 = if (@as(u32, @truncate(self.regs.rcx)) == 0) x64_decoder.emulatedXcr0() else 0;
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(xcr0));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(xcr0 >> 32));
            },

            .hlt => {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.hlt);
                self.terminated = true;
                self.exit_code = self.regs.rax;
            },

            else => {
                log.warn("unimplemented instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
                self.faulted = true;
                self.exit_code = 127;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
                self.terminated = true;
            },
        }
    }

    fn executeAddRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        const a = self.regVal(d.dst_reg, sz);
        const r = a +% d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsAdd(a, d.imm, r, sz);
    }

    fn executeSubRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        const a = self.regVal(d.dst_reg, sz);
        const r = a -% d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsSub(a, d.imm, r, sz);
    }

    fn executeAndRegImm(self: *MachOState, d: DecodedInsn) void {
        const sz = d.size;
        const a = self.regVal(d.dst_reg, sz);
        const r = a & d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsLogic(r, sz);
    }

    fn dispatchMacOSSyscall(self: *MachOState, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        const number = self.regs.rax;
        log.info("syscall: number=0x{x} ({s}) args=({d}, {d}, {d}, {d}, {d}, {d})", .{
            number, macho_runtime.syscallName(number),
            arg1,   arg2,
            arg3,   arg4,
            arg5,   arg6,
        });

        switch (number) {
            @intFromEnum(macho_runtime.Syscall.exit) => {
                const exit_code = arg1;
                log.info("exit({d})", .{exit_code});
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                self.terminated = true;
                self.exit_code = exit_code;
            },
            @intFromEnum(macho_runtime.Syscall.write) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemoryConst(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd: i32 = if (fd < self.guest_fds.len) self.guest_fds[@as(usize, @intCast(fd))] else -1;
                var written: usize = 0;
                if (host_fd >= 0) {
                    while (written < data.len) {
                        const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
                        if (n <= 0) {
                            self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                            return;
                        }
                        written += @as(usize, @intCast(n));
                    }
                }
                self.regs.rax = @intCast(written);
            },
            @intFromEnum(macho_runtime.Syscall.read) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemory(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd: i32 = if (fd < self.guest_fds.len) self.guest_fds[@as(usize, @intCast(fd))] else -1;
                if (host_fd >= 0) {
                    const n = std.c.read(host_fd, data.ptr, data.len);
                    if (n < 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                    self.regs.rax = @intCast(@as(usize, @intCast(n)));
                } else {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                }
            },
            @intFromEnum(macho_runtime.Syscall.mmap) => {
                const addr = arg1;
                const length = arg2;
                const prot = arg3;

                const alignment = PAGE_SIZE;
                const aligned_length = ((length + alignment - 1) / alignment) * alignment;

                if (addr != 0) {
                    const off = self.addrToOffset(addr) orelse {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    };
                    if (off + aligned_length <= self.mem_size) {
                        if (prot & 0x01 != 0) {
                            @memset(self.mem[off..][0..@as(usize, @intCast(aligned_length))], 0);
                        }
                        self.regs.rax = addr;
                        return;
                    }
                }

                var next_addr = self.mem_base;
                while (next_addr + aligned_length <= self.mem_size) : (next_addr += alignment) {
                    const off = self.addrToOffset(next_addr) orelse break;
                    if (off + aligned_length > self.mem_size) break;
                    var free_range = true;
                    var i: usize = 0;
                    while (i < aligned_length) : (i += alignment) {
                        if (next_addr + i == self.regs.rsp) {
                            free_range = false;
                            break;
                        }
                    }
                    if (!free_range) {
                        next_addr += aligned_length;
                    }
                    if (free_range) {
                        self.regs.rax = next_addr;
                        return;
                    }
                }
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            },
            @intFromEnum(macho_runtime.Syscall.mprotect) => {
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.munmap) => {
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.getpid) => {
                self.regs.rax = 42;
            },
            @intFromEnum(macho_runtime.Syscall.issetugid) => {
                self.regs.rax = 0;
            },
            0x2000072 => {
                self.regs.rax = 1;
            },
            else => {
                log.warn("unimplemented syscall: 0x{x}", .{number});
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            },
        }
    }
};

fn alignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);
}

fn parseFopenFlags(mode: []const u8) ?i32 {
    if (mode.len == 0) return null;
    var flags: i32 = 0;
    switch (mode[0]) {
        'r' => flags = 0x0000,
        'w' => flags = 0x0001 | 0x0200 | 0x0400,
        'a' => flags = 0x0001 | 0x0200 | 0x0008,
        else => return null,
    }
    if (std.mem.indexOfScalar(u8, mode, '+') != null) {
        flags &= ~@as(i32, 0x0003);
        flags |= 0x0002;
    }
    return flags;
}

fn alignUp(value: u64, alignment: u64) !u64 {
    const mask = alignment - 1;
    return (try std.math.add(u64, value, mask)) & ~mask;
}

pub const MachORunOptions = struct {
    path: []const u8,
    args: []const []const u8 = &.{},
    trace: bool = false,
};

pub fn loadAndRun(io: std.Io, allocator: std.mem.Allocator, options: MachORunOptions) !u64 {
    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, options.path, allocator, .unlimited);
    defer allocator.free(file_data);

    const slice = extractX8664Slice(allocator, file_data) catch |err| {
        std.debug.print("macho-processor: not a valid x86_64 Mach-O binary: {s}\n", .{@errorName(err)});
        return 1;
    };

    var state = try MachOState.init(allocator, slice);
    defer state.deinit();

    var temp_state = try macho.load(allocator, slice);
    defer temp_state.deinit();

    std.debug.print("macho-processor: {s}\n", .{options.path});
    std.debug.print("  filetype: 0x{x}", .{temp_state.header.filetype});
    switch (temp_state.header.filetype) {
        2 => std.debug.print(" (MH_EXECUTE)\n", .{}),
        6 => std.debug.print(" (MH_DYLIB)\n", .{}),
        8 => std.debug.print(" (MH_BUNDLE)\n", .{}),
        else => std.debug.print("\n", .{}),
    }
    std.debug.print("  cputype:  0x{x}", .{temp_state.header.cputype});
    if (temp_state.header.cputype == macho.CPU_TYPE_X86_64) std.debug.print(" (x86_64)\n", .{}) else std.debug.print("\n", .{});
    std.debug.print("  ncmds:    {d}\n", .{temp_state.header.ncmds});
    std.debug.print("  segments: {d}\n", .{temp_state.segments.len});
    std.debug.print("  entry:    0x{x}\n", .{temp_state.entry_point});
    std.debug.print("  stack:    0x{x}\n", .{temp_state.stack_size});
    std.debug.print("  mem_base: 0x{x}\n", .{state.mem_base});
    std.debug.print("  entry_vaddr: 0x{x}\n", .{state.entry_point_vaddr});
    std.debug.print("  dylibs:    {d}\n", .{state.metadata.dylibs.len});
    std.debug.print("  imports:   {d}\n", .{state.metadata.imports.len});
    std.debug.print("  initializers: {d}\n", .{state.metadata.initializer_count});
    if (state.metadata.nearestSymbol(state.entry_point_vaddr)) |entry_symbol| {
        std.debug.print("  entry_symbol: {s}+0x{x}\n", .{ entry_symbol.name, entry_symbol.offset });
    }

    for (temp_state.segments, 0..) |seg, i| {
        const prot_str = switch (seg.initprot) {
            7 => "rwx",
            5 => "r-x",
            3 => "rw-",
            1 => "r--",
            else => "???",
        };
        std.debug.print("    [{d}] {s: <12}  vm=0x{x:0>8}  size=0x{x:0>8}  file=0x{x:0>8}  ({s})\n", .{
            i, seg.name, seg.vmaddr, seg.vmsize, seg.fileoff, prot_str,
        });
    }

    if (temp_state.entry_point == 0) {
        std.debug.print("macho-processor: no entry point found\n", .{});
        return 1;
    }

    state.guest_fds[0] = 0;
    state.guest_fds[1] = 1;
    state.guest_fds[2] = 2;

    state.setupMachOState(options.path, options.args);

    std.debug.print("macho-processor: starting execution at 0x{x}, rsp=0x{x}\n", .{ state.regs.rip, state.regs.rsp });

    state.run();

    std.debug.print("macho-processor: execution finished: exit_code={d}, faulted={}, terminated={}\n", .{ state.exit_code, state.faulted, state.terminated });

    if (state.unresolved_import_count != 0) {
        const end = if (state.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else state.import_trace_index;
        for (0..end) |i| {
            const entry = state.import_trace_entries[i];
            if (entry.caller_symbol.len != 0) {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} caller={s}+0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.caller_symbol, entry.caller_offset, entry.synthetic_result },
                );
            } else {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.synthetic_result },
                );
            }
        }
    }

    if (state.unresolved_import_count != 0 and !state.faulted) {
        std.debug.print(
            "macho-processor: runtime incomplete: {d} unresolved import call(s); guest exit {d} is diagnostic only, returning processor status {d}\n",
            .{ state.unresolved_import_count, state.exit_code, UNSUPPORTED_RUNTIME_EXIT_CODE },
        );
        return UNSUPPORTED_RUNTIME_EXIT_CODE;
    }

    return state.exit_code;
}

fn extractX8664Slice(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    return fat.extractX8664Slice(allocator, data) catch |err| {
        if (err == error.NotMachO) return error.NotMachO;
        if (err == error.NoX86_64Slice) {
            std.debug.print("macho-processor: no x86_64 slice found in fat binary\n", .{});
            return error.NoX86_64Slice;
        }
        return err;
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};
    var pos: usize = 0;
    var d = DecodedInsn{};
    var rex: u8 = 0;
    var has_66: bool = false;
    var has_f0: bool = false;
    var has_f2: bool = false;
    var has_f3: bool = false;
    var has_0f: bool = false;

    while (pos < bytes.len) {
        switch (bytes[pos]) {
            0x66 => {
                has_66 = true;
                pos += 1;
            },
            0x67 => {
                pos += 1;
            },
            0xF0 => {
                has_f0 = true;
                pos += 1;
            },
            0xF2 => {
                has_f2 = true;
                pos += 1;
            },
            0xF3 => {
                has_f3 = true;
                pos += 1;
            },
            0x40...0x4F => {
                rex = bytes[pos];
                pos += 1;
            },
            else => break,
        }
    }

    if (pos >= bytes.len) return .{};

    const rex_w = (rex & 0x08) != 0;
    const rex_r = (rex & 0x04) != 0;
    const rex_x = (rex & 0x02) != 0;
    const rex_b = (rex & 0x01) != 0;

    const op_size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    _ = op_size;

    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode = bytes[pos];

    if (opcode == 0x0F) {
        pos += 1;
        if (pos >= bytes.len) return .{};
        has_0f = true;
        return decodeTwoByte(bytes, &pos, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, rex);
    }

    if (opcode == 0x90) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos + 1));
        return d;
    }

    switch (opcode) {
        0x50...0x57 => {
            d.op = .push_reg;
            const reg_num: u8 = opcode - 0x50;
            d.dst_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x58...0x5F => {
            d.op = .pop_reg;
            const reg_num: u8 = opcode - 0x58;
            d.dst_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x68, 0x6A => {
            d.op = .push_imm;
            if (opcode == 0x68) {
                if (pos + 5 > bytes.len) return .{};
                d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.len = 6;
            } else {
                if (pos + 2 > bytes.len) return .{};
                d.imm = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
                d.len = 2;
            }
        },

        0xAC, 0xAD => {
            d.op = .lods;
            d.size = if (opcode == 0xAC) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x69, 0x6B => {
            return decodeImulImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x70...0x7F => {
            d.op = .jcc_rel8;
            d.cond = mapJccCond8(opcode);
            if (pos + 2 > bytes.len) return .{};
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0x84, 0x85 => {
            return decodeTestRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x86, 0x87 => {
            return decodeXchgRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x88, 0x89, 0x8A, 0x8B => {
            return decodeMovRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x8D => {
            return decodeLea(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x8F => {
            return decodePopRm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x00...0x03 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .add);
        },
        0x08...0x0B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"or");
        },
        0x20...0x23 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"and");
        },
        0x28...0x2B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .sub);
        },
        0x30...0x33 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .xor);
        },
        0x38...0x3B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .cmp);
        },

        0x80...0x83 => {
            return decodeGroup1Imm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3 => {
            return decodeGroup2Shift(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xF6, 0xF7 => {
            return decodeGroup3(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xB0...0xB7 => {
            d.op = .mov_reg_imm;
            d.dst_reg = mapReg(opcode - 0xB0, rex_b);
            d.size = .bits8;
            if (pos + 2 > bytes.len) return .{};
            d.imm = bytes[pos + 1];
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xC2, 0xC3 => {
            d.op = .ret;
            if (opcode == 0xC2) {
                if (pos + 3 > bytes.len) return .{};
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                d.len = 3;
            } else {
                d.imm = 0;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },

        0xC6, 0xC7 => {
            return decodeMovMemImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xCC => {
            d.op = .hlt;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0xE8 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .call_rel32;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },

        0xE9 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },
        0xEB => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0xFE, 0xFF => {
            return decodeGroup4_5(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x98 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x99 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9B => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x0D => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .or_reg8_reg8;
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.dst_reg = mapReg(0, rex_b);
            d.imm = switch (sz) {
                .bits8 => bytes[pos + 1],
                .bits16 => std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little),
                else => std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little),
            };
            d.len = if (sz == .bits8) 2 else if (sz == .bits16) 3 else 5;
        },

        0x25 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .and_reg8_imm8;
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.dst_reg = mapReg(0, rex_b);
            d.imm = switch (sz) {
                .bits8 => bytes[pos + 1],
                .bits16 => std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little),
                else => std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little),
            };
            d.len = if (sz == .bits8) 2 else if (sz == .bits16) 3 else 5;
        },

        0x35 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .xor_reg8_reg8;
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.dst_reg = mapReg(0, rex_b);
            d.imm = switch (sz) {
                .bits8 => bytes[pos + 1],
                .bits16 => std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little),
                else => std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little),
            };
            d.len = if (sz == .bits8) 2 else if (sz == .bits16) 3 else 5;
        },

        0x3D => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .cmp_reg8_imm8;
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.dst_reg = mapReg(0, rex_b);
            d.imm = switch (sz) {
                .bits8 => bytes[pos + 1],
                .bits16 => std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little),
                else => std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little),
            };
            d.len = if (sz == .bits8) 2 else if (sz == .bits16) 3 else 5;
        },

        0x8C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xA8 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .test_reg8_imm8;
            d.size = .bits8;
            d.dst_reg = .al_ax_eax_rax;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0xA9 => {
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            const imm_len: usize = if (sz == .bits16) 2 else 4;
            if (pos + 1 + imm_len > bytes.len) return .{};
            d.op = switch (sz) {
                .bits16 => .test_reg16_imm16,
                .bits32 => .test_reg32_imm32,
                .bits64 => .test_reg64_imm32,
                .bits8 => unreachable,
            };
            d.size = sz;
            d.dst_reg = .al_ax_eax_rax;
            if (sz == .bits16) {
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
            } else {
                const imm32 = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.imm = if (sz == .bits64)
                    @bitCast(@as(i64, @as(i32, @bitCast(imm32))))
                else
                    imm32;
            }
            d.len = @intCast(pos + 1 + imm_len);
        },

        0xB8...0xBF => {
            d.op = .mov_reg_imm;
            d.dst_reg = mapReg(opcode - 0xB8, rex_b);
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.size = sz;
            switch (sz) {
                .bits16 => {
                    if (pos + 3 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                    d.len = @as(u8, @intCast(pos + 3));
                },
                .bits32 => {
                    if (pos + 5 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                    d.len = @as(u8, @intCast(pos + 5));
                },
                .bits64 => {
                    if (pos + 9 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u64, bytes[pos + 1 ..][0..8], .little);
                    d.len = @as(u8, @intCast(pos + 9));
                },
                .bits8 => unreachable,
            }
        },

        0x0C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .or_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x14 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .adc_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x1C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sbb_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x24 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .and_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x2C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sub_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x34 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .xor_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x3C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .cmp_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x04 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .add_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0x40...0x47 => {
            if (opcode == 0x40) {
                d.op = .nop;
            } else {
                d.op = .inc_reg64;
                const reg_num: u8 = opcode - 0x40;
                d.dst_reg = mapReg(reg_num, false);
            }
            d.len = @as(u8, @intCast(pos + 1));
        },

        0xC9 => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x6C, 0x6D, 0x6E, 0x6F => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9D => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9E => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        else => {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos + 1));
        },
    }

    return d;
}

fn decodeTwoByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, _: u8) DecodedInsn {
    var d = DecodedInsn{};
    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode2 = bytes[pos.*];
    pos.* += 1;

    if (opcode2 == 0x05) {
        d.op = .syscall;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x1F) {
        while (pos.* < bytes.len and bytes[pos.*] == 0x1F) pos.* += 1;
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x80 and opcode2 <= 0x8F) {
        d.op = .jcc_rel32;
        d.cond = mapJccCond32(opcode2);
        if (pos.* + 4 > bytes.len) return .{};
        d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
        d.rip_relative = true;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x90 and opcode2 <= 0x9F) {
        return decodeSetcc(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xA2) {
        d.op = .cpuid;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x01 and pos.* < bytes.len and bytes[pos.*] == 0xD0) {
        pos.* += 1;
        d.op = .xgetbv;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0xAF) {
        return decodeImulTwoOp(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB0 or opcode2 == 0xB1) {
        return decodeCmpxchg(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB6 or opcode2 == 0xB7) {
        return decodeMovzx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xBE or opcode2 == 0xBF) {
        return decodeMovsx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xC1) {
        return decodeXadd(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0x10 or opcode2 == 0x11) {
        return decodeMovupsMovss(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x28 or opcode2 == 0x29) {
        return decodeMovaps(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0x2E or opcode2 == 0x2F) {
        d.op = .nop;
        const extra = if (pos.* + 1 <= bytes.len and hasModRM(bytes[pos.*])) @as(u8, 1) else @as(u8, 0);
        d.len = @as(u8, @intCast(pos.* + extra));
        return d;
    }

    if (opcode2 == 0x38) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x38);
    }

    if (opcode2 == 0x3A) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x3A);
    }

    if (opcode2 == 0x40 or opcode2 == 0x41) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x50 or opcode2 == 0x51) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x54) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x55) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x56) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"or");
    }

    if (opcode2 == 0x57) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .xor);
    }

    if (opcode2 == 0x58 or opcode2 == 0x59 or opcode2 == 0x5C or opcode2 == 0x5E or opcode2 == 0x5F) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0x70) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 3));
        return d;
    }

    if (opcode2 == 0xD1 or opcode2 == 0xD2 or opcode2 == 0xD3) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xE6) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xEF) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xF1 or opcode2 == 0xF2 or opcode2 == 0xF3 or opcode2 == 0xF4 or opcode2 == 0xF5) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xAE) {
        if (pos.* < bytes.len) {
            const modrm = bytes[pos.*];
            const reg = (modrm >> 3) & 7;
            if (reg == 5 or reg == 6 or reg == 7) {
                d.op = .nop;
                d.len = @as(u8, @intCast(pos.* + 1));
                return d;
            }
        }
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 1));
        return d;
    }

    d.op = .nop;
    d.len = @as(u8, @intCast(pos.*));
    return d;
}

fn decodeThreeByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode: u8) DecodedInsn {
    _ = has_66;
    _ = has_f2;
    _ = has_f3;
    _ = opcode;
    if (pos.* >= bytes.len) return .{};
    const opcode3 = bytes[pos.*];
    if (opcode3 == 0xF5 or opcode3 == 0xF7 or opcode3 == 0xFA or opcode3 == 0xFB or opcode3 == 0xFC) {
        pos.* += 1;
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, false, opcode3, .nop);
    }
    var d = DecodedInsn{};
    d.op = .nop;
    d.len = @as(u8, @intCast(pos.* + 1));
    return d;
}

fn decodeSseBytes(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, sse_op: anytype) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    _ = opcode;
    var d = DecodedInsn{};
    if (pos.* >= bytes.len) return .{};
    const modrm = bytes[pos.*];
    const is_reg = modrm >= 0xC0;
    if (is_reg) {
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.xmm_dst = @intFromEnum(rm.reg);
        d.xmm_src = @intFromEnum(@as(RegId, @enumFromInt(@as(u8, @intCast(rm.addr)))));
        if (comptime std.mem.eql(u8, @tagName(sse_op), "xor")) {
            d.op = .xorps_xmm_xmm;
        } else {
            d.op = .nop;
        }
        d.len = @as(u8, @intCast(pos.*));
        return d;
    } else {
        _ = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }
}

fn hasModRM(byte: u8) bool {
    _ = byte;
    return true;
}

fn mapReg(reg_num: u8, rex_b: bool) RegId {
    const r = reg_num + @as(u8, if (rex_b) 8 else 0);
    return @enumFromInt(r);
}

fn mapJccCond8(opcode: u8) Cond {
    const conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };
    return conditions[opcode & 0x0F];
}

fn mapJccCond32(opcode: u8) Cond {
    const conditions: [12]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np,
    };
    const idx = opcode & 0x0F;
    if (idx < 12) return conditions[idx];
    if (idx == 12) return .l;
    if (idx == 13) return .ge;
    if (idx == 14) return .le;
    return .g;
}

fn readModRM(d: *DecodedInsn, bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, _: Size) struct { reg: RegId, addr: u64 } {
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mod = (modrm >> 6) & 3;
    const reg_num = (modrm >> 3) & 7;
    const rm_num = modrm & 7;

    const reg = mapReg(reg_num, rex_r);

    d.sib_has_base = false;
    d.sib_has_index = false;
    d.rip_relative = false;
    d.is_reg_form = false;

    if (mod == 3) {
        d.is_reg_form = true;
        return .{ .reg = reg, .addr = @as(u64, @intFromEnum(mapReg(rm_num, rex_b))) };
    }

    var disp: u64 = 0;

    if (rm_num == 4) {
        const sib = bytes[pos.*];
        pos.* += 1;
        const scale = (sib >> 6) & 3;
        const index_num = (sib >> 3) & 7;
        const base_num = sib & 7;

        if (index_num != 4) {
            d.sib_has_index = true;
            d.sib_index_reg = mapReg(index_num, rex_x);
            d.sib_scale = @as(u2, @intCast(scale));
        }

        if (mod == 0 and base_num == 5) {
            d.rip_relative = true;
        } else {
            d.sib_has_base = true;
            d.sib_base_reg = mapReg(base_num, rex_b);
        }

        if (mod == 0 and base_num == 5) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        } else if (mod == 1) {
            disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
            pos.* += 1;
        } else if (mod == 2) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        }
        return .{ .reg = reg, .addr = disp };
    }

    if (mod == 0 and rm_num == 5) {
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        d.rip_relative = true;
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else if (mod == 1) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
        pos.* += 1;
    } else if (mod == 2) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
    }

    return .{ .reg = reg, .addr = disp };
}

fn decodeArithRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, arith_type: enum { add, @"or", adc, sbb, @"and", sub, xor, cmp }) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    const is_byte = (opcode & 0x01) == 0;
    const sz: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
    const is_reg_reg = bytes[start_pos + 1] >= 0xC0;
    const is_mem_to_reg = (opcode & 0x02) != 0;

    const reg_mem_ops: [8]Op = .{
        .add_reg8_mem8, .or_reg8_mem8,  .adc_reg8_mem8, .sbb_reg8_mem8,
        .and_reg8_mem8, .sub_reg8_mem8, .xor_reg8_mem8, .cmp_reg8_mem8,
    };
    const mem_reg_ops: [8]Op = .{
        .add_mem8_reg8, .or_mem8_reg8,  .invalid,       .invalid,
        .and_mem8_reg8, .sub_mem8_reg8, .xor_mem8_reg8, .cmp_mem8_reg8,
    };
    const reg_reg_ops: [8]Op = .{
        .add_reg8_reg8, .or_reg8_reg8,  .invalid,       .invalid,
        .and_reg8_reg8, .sub_reg8_reg8, .xor_reg8_reg8, .cmp_reg8_reg8,
    };

    const base_op = if (is_reg_reg)
        reg_reg_ops[@intFromEnum(arith_type)]
    else if (is_mem_to_reg)
        reg_mem_ops[@intFromEnum(arith_type)]
    else
        mem_reg_ops[@intFromEnum(arith_type)];
    const off = @intFromEnum(sz) - @intFromEnum(Size.bits8);
    d.op = if (base_op == .invalid)
        .invalid
    else
        @enumFromInt(@intFromEnum(base_op) + off);

    if (is_reg_reg) {
        if (is_mem_to_reg) {
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        }
        d.is_reg_form = true;
    } else if (is_mem_to_reg) {
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.src_reg = rm.reg;
        d.addr = rm.addr;
    }
    d.size = sz;
    d.len = @as(u8, @intCast(pos));

    return d;
}

fn decodeMovRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    _ = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x88 or opcode == 0x8A) .bits8 else .bits32;

    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];

    const to_reg = (opcode & 0x02) != 0;
    const byte_op = opcode == 0x88 or opcode == 0x8A;

    const actual_sz: Size = if (byte_op) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, actual_sz);
    const is_reg = modrm >= 0xC0;

    if (to_reg) {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_mem8,
                .bits16 => .mov_reg16_mem16,
                .bits32 => .mov_reg32_mem32,
                .bits64 => .mov_reg64_mem64,
            };
            d.dst_reg = rm.reg;
            d.addr = rm.addr;
        }
    } else {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_mem8_reg8,
                .bits16 => .mov_mem16_reg16,
                .bits32 => .mov_mem32_reg32,
                .bits64 => .mov_mem64_reg64,
            };
            d.addr = rm.addr;
            d.src_reg = rm.reg;
        }
    }

    d.size = actual_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeLea(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (modrm < 0xC0) {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        d.op = .lea_reg_mem;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
        d.size = sz;
        d.len = @as(u8, @intCast(pos));
        return d;
    }
    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodePopRm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits64;
    _ = sz;
    if (modrm >= 0xC0) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .pop_reg;
        d.dst_reg = @enumFromInt(rm.addr);
    } else {
        d.op = .pop_mem64;
        d.addr = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64).addr;
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup1Imm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x80) .bits8 else .bits32;

    const is_byte_imm = opcode == 0x80 or opcode == 0x83;
    const imm_size: u8 = if (is_byte_imm) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (is_byte_imm)
        if (opcode == 0x83) @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos]))))) else bytes[pos]
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    const base_sz = if (sz == .bits8) Size.bits8 else if (sz == .bits16) Size.bits16 else if (sz == .bits32) Size.bits32 else Size.bits64;

    const group_ops: [8]Op = .{
        .add_reg8_imm8, .or_reg8_imm8,  .adc_reg8_imm8, .sbb_reg8_imm8,
        .and_reg8_imm8, .sub_reg8_imm8, .xor_reg8_imm8, .cmp_reg8_imm8,
    };

    if (is_mem) {
        const mem_group_ops: [8]Op = .{
            .add_mem8_imm8, .invalid, .invalid, .invalid,
            .invalid,       .invalid, .invalid, .cmp_mem8_imm8,
        };
        const base = mem_group_ops[group_op];
        if (base == .invalid) {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos));
            return d;
        }
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.addr = rm.addr;
    } else {
        const base = group_ops[group_op];
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.size = base_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup2Shift(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode == 0xC0 or opcode == 0xD0 or opcode == 0xD2;
    const size: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const uses_cl = opcode == 0xD2 or opcode == 0xD3;

    if (group_op != 4 and group_op != 5 and group_op != 7) {
        d.op = .invalid;
        d.len = @intCast(pos + 1);
        return d;
    }
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, size);
    const count: u64 = if (opcode == 0xC0 or opcode == 0xC1) blk: {
        if (pos >= bytes.len) return .{};
        const immediate = bytes[pos];
        pos += 1;
        break :blk immediate;
    } else if (uses_cl) 0 else 1;

    if (uses_cl) {
        d.op = if (is_mem)
            switch (group_op) {
                4 => .shl_mem_cl,
                5 => .shr_mem_cl,
                else => .sar_mem_cl,
            }
        else switch (group_op) {
            4 => .shl_reg_cl,
            5 => .shr_reg_cl,
            else => .sar_reg_cl,
        };
    } else if (is_mem) {
        d.op = switch (group_op) {
            4 => .shl_mem_imm,
            5 => .shr_mem_imm,
            else => .sar_mem_imm,
        };
    } else {
        d.op = switch (group_op) {
            4 => .shl_reg_imm,
            5 => .shr_reg_imm,
            else => .sar_reg_imm,
        };
    }
    d.size = size;
    d.imm = count;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
    }
    d.len = @intCast(pos);
    return d;
}

fn decodeMovMemImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    _ = modrm;

    if (opcode == 0xC6) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        d.op = .mov_mem8_imm8;
        d.addr = rm.addr;
        d.imm = bytes[pos];
        pos += 1;
    } else {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        if (sz == .bits16) {
            if (pos + 2 > bytes.len) return .{};
            d.op = .mov_mem16_imm16;
            d.imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
            pos += 2;
        } else if (sz == .bits64) {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem64_imm32;
            d.imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            pos += 4;
        } else {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem32_imm32;
            d.imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            pos += 4;
        }
        d.addr = rm.addr;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup3(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};

    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const sz: Size = if (opcode == 0xF6) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (group != 0 and group != 1) {
        d.op = .invalid;
        d.len = @intCast(pos);
        return d;
    }

    const imm_len: usize = switch (sz) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32, .bits64 => 4,
    };
    if (pos + imm_len > bytes.len) return .{};
    d.imm = switch (sz) {
        .bits8 => bytes[pos],
        .bits16 => std.mem.readInt(u16, bytes[pos..][0..2], .little),
        .bits32 => std.mem.readInt(u32, bytes[pos..][0..4], .little),
        .bits64 => @bitCast(@as(i64, @as(i32, @bitCast(std.mem.readInt(u32, bytes[pos..][0..4], .little))))),
    };
    pos += imm_len;
    const base_op: Op = if (is_mem) .test_mem8_imm8 else .test_reg8_imm8;
    d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
    d.size = sz;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.len = @intCast(pos);
    return d;
}

fn decodeGroup4_5(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    if (opcode == 0xFE) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        if (group == 0) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else if (group == 1) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else {
            d.op = .invalid;
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    if (opcode == 0xFF) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        switch (group) {
            0 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            1 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            2 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            3 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            4 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            5 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            6 => {
                if (is_mem) {
                    d.op = .push_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .push_reg;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            else => {
                d.op = .invalid;
            },
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeTestRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x84) .bits8 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits8 => .test_mem8_reg8,
            .bits16 => .test_mem16_reg16,
            .bits32 => .test_mem32_reg32,
            .bits64 => .test_mem64_reg64,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits8 => .test_reg8_reg8,
            .bits16 => .test_reg16_reg16,
            .bits32 => .test_reg32_reg32,
            .bits64 => .test_reg64_reg64,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeXchgRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, _: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .xchg_mem32_reg32,
            .bits64 => .xchg_mem64_reg64,
            else => .invalid,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits32 => .xchg_mem32_reg32,
            .bits64 => .xchg_mem64_reg64,
            else => .invalid,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeImulImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const imm_is_byte = opcode == 0x6B;
    const imm_size: usize = if (imm_is_byte) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (imm_is_byte)
        @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos])))))
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32_imm8,
            .bits64 => .imul_reg64_mem64_imm8,
            else => .imul_reg32_mem32_imm8,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32_imm8,
            .bits64 => .imul_reg64_reg64_imm8,
            else => .imul_reg32_reg32_imm8,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeImulTwoOp(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32,
            .bits64 => .imul_reg64_mem64,
            else => .imul_reg32_mem32,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32,
            .bits64 => .imul_reg64_reg64,
            else => .imul_reg32_reg32,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeCmpxchg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .cmpxchg_mem32_reg32,
            .bits64 => .cmpxchg_mem64_reg64,
            else => .cmpxchg_mem32_reg32,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits32 => .cmpxchg_mem32_reg32,
            .bits64 => .cmpxchg_mem64_reg64,
            else => .cmpxchg_mem32_reg32,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovzx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xB6;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovsx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xBE;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeXadd(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .xadd_mem32_reg32,
            .bits64 => .xadd_mem64_reg64,
            else => .xadd_mem32_reg32,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeSetcc(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);

    const setcc_conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };

    if (is_mem) {
        d.op = .setcc_mem8;
        d.addr = rm.addr;
    } else {
        d.op = .setcc_reg8;
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.cond = setcc_conditions[opcode2 & 0x0F];
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovupsMovss(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    _ = has_f2;
    _ = has_f3;
    _ = opcode2;
    _ = rex_r;
    _ = rex_x;
    _ = rex_b;
    var d = DecodedInsn{};
    d.op = .nop;
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (modrm < 0xC0) {
        pos += 1;
        if (modrm & 0x07 == 4) pos += 1;
        const disp_size: u8 = if ((modrm >> 6) == 1) 1 else if ((modrm >> 6) == 2) 4 else 0;
        pos += disp_size;
    } else {
        pos += 1;
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovaps(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const to_reg = opcode2 == 0x28;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);

    if (to_reg) {
        if (is_mem) {
            d.op = .movaps_xmm_mem;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
        }
    } else {
        if (is_mem) {
            d.op = .movaps_mem_xmm;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
        }
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

test "decode Xbyak shl ecx immediate" {
    const decoded = decodeInsn(&[_]u8{ 0xC1, 0xE1, 0x08 });
    try std.testing.expectEqual(Op.shl_reg_imm, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 8), decoded.imm);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode group two implicit and arithmetic shifts" {
    const shr = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try std.testing.expectEqual(Op.shr_reg_imm, shr.op);
    try std.testing.expectEqual(@as(u64, 1), shr.imm);
    try std.testing.expectEqual(@as(u8, 2), shr.len);

    const sar = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try std.testing.expectEqual(Op.sar_reg_imm, sar.op);
    try std.testing.expectEqual(Size.bits64, sar.size);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, sar.dst_reg);
    try std.testing.expectEqual(@as(u64, 3), sar.imm);
    try std.testing.expectEqual(@as(u8, 4), sar.len);

    const shr_cl = decodeInsn(&[_]u8{ 0xD3, 0xE8 });
    try std.testing.expectEqual(Op.shr_reg_cl, shr_cl.op);
    try std.testing.expectEqual(Size.bits32, shr_cl.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shr_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), shr_cl.len);

    const sar_cl = decodeInsn(&[_]u8{ 0xD3, 0xF8 });
    try std.testing.expectEqual(Op.sar_reg_cl, sar_cl.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sar_cl.dst_reg);
}

test "decode register MOVZX without consuming the following instruction" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xB6, 0xC0, 0x48, 0x83, 0xC4, 0x30 });
    try std.testing.expectEqual(Op.movzx_reg32_mem8, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.src_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode MOVSX memory and accumulator byte immediate forms" {
    const movsx = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBE, 0x48, 0x03 });
    try std.testing.expectEqual(Op.movsx_reg32_mem8, movsx.op);
    try std.testing.expectEqual(Size.bits64, movsx.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, movsx.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, movsx.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), movsx.addr);
    try std.testing.expectEqual(@as(u8, 5), movsx.len);

    const and_al = decodeInsn(&[_]u8{ 0x24, 0x01 });
    try std.testing.expectEqual(Op.and_reg8_imm8, and_al.op);
    try std.testing.expectEqual(Size.bits8, and_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), and_al.imm);
    try std.testing.expectEqual(@as(u8, 2), and_al.len);
}

test "decode accumulator TEST immediate forms" {
    const test_al = decodeInsn(&[_]u8{ 0xA8, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_al.op);
    try std.testing.expectEqual(Size.bits8, test_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, test_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_al.imm);
    try std.testing.expectEqual(@as(u8, 2), test_al.len);

    const test_rax = decodeInsn(&[_]u8{ 0x48, 0xA9, 0x00, 0x00, 0x00, 0x80 });
    try std.testing.expectEqual(Op.test_reg64_imm32, test_rax.op);
    try std.testing.expectEqual(Size.bits64, test_rax.size);
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_8000_0000), test_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), test_rax.len);
}

test "decode full near conditional jump range" {
    const jc = decodeInsn(&[_]u8{ 0x0F, 0x82, 0xA7, 0x01, 0x00, 0x00 });
    try std.testing.expectEqual(Op.jcc_rel32, jc.op);
    try std.testing.expectEqual(Cond.b, jc.cond);
    try std.testing.expectEqual(@as(u64, 0x1A7), jc.addr);
    try std.testing.expect(jc.rip_relative);
    try std.testing.expectEqual(@as(u8, 6), jc.len);
}

test "decode both directions of 64-bit AND memory operands" {
    const load_and = decodeInsn(&[_]u8{ 0x48, 0x23, 0x08 });
    try std.testing.expectEqual(Op.and_reg64_mem64, load_and.op);
    try std.testing.expectEqual(Size.bits64, load_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_and.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), load_and.len);

    const store_and = decodeInsn(&[_]u8{ 0x48, 0x21, 0x08 });
    try std.testing.expectEqual(Op.and_mem64_reg64, store_and.op);
    try std.testing.expectEqual(Size.bits64, store_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, store_and.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), store_and.len);
}

test "decode arithmetic byte width and operand direction" {
    const xor_al = decodeInsn(&[_]u8{ 0x30, 0xC0 });
    try std.testing.expectEqual(Op.xor_reg8_reg8, xor_al.op);
    try std.testing.expectEqual(Size.bits8, xor_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.src_reg);

    const sub_mem = decodeInsn(&[_]u8{ 0x29, 0x08 });
    try std.testing.expectEqual(Op.sub_mem32_reg32, sub_mem.op);
    try std.testing.expectEqual(Size.bits32, sub_mem.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, sub_mem.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sub_mem.sib_base_reg);
}

test "decode group three TEST register immediate" {
    const test_cl = decodeInsn(&[_]u8{ 0xF6, 0xC1, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_cl.op);
    try std.testing.expectEqual(Size.bits8, test_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, test_cl.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_cl.imm);
    try std.testing.expectEqual(@as(u8, 3), test_cl.len);
}

test "decode CPUID and XGETBV" {
    const cpuid = decodeInsn(&[_]u8{ 0x0F, 0xA2 });
    try std.testing.expectEqual(Op.cpuid, cpuid.op);
    try std.testing.expectEqual(@as(u8, 2), cpuid.len);

    const xgetbv = decodeInsn(&[_]u8{ 0x0F, 0x01, 0xD0 });
    try std.testing.expectEqual(Op.xgetbv, xgetbv.op);
    try std.testing.expectEqual(@as(u8, 3), xgetbv.len);
}

test "decode non-W REX prefixes used by CPUID result copies" {
    const mov_r9d_eax = decodeInsn(&[_]u8{ 0x41, 0x89, 0xC1 });
    try std.testing.expectEqual(Op.mov_reg32_reg32, mov_r9d_eax.op);
    try std.testing.expectEqual(Size.bits32, mov_r9d_eax.size);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_r9d_eax.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, mov_r9d_eax.src_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_r9d_eax.len);

    const mov_mem_r9d = decodeInsn(&[_]u8{ 0x45, 0x89, 0x08 });
    try std.testing.expectEqual(Op.mov_mem32_reg32, mov_mem_r9d.op);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_mem_r9d.src_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, mov_mem_r9d.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_mem_r9d.len);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("usage: macho_processor <binary> [args...]\n", .{});
        std.process.exit(1);
    }

    const exit_code = try loadAndRun(init.io, allocator, .{
        .path = args[1],
        .args = args[2..],
    });
    std.process.exit(@intCast(exit_code));
}
