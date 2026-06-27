const std = @import("std");
const macho = @import("macho.zig");
const fat = @import("fat.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const macho_runtime = @import("macho_runtime");

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

const STACK_SIZE: u64 = 8 * 1024 * 1024;
const MEM_SIZE: u64 = 512 * 1024 * 1024;
const MEM_BASE: u64 = 0x0;
const PAGE_SIZE: u64 = 4096;

const MachSegment = macho.MachSegment;

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
    data: []const u8,
    segments: []const MachSegment,
    entry_point_vaddr: u64 = 0,
    stack_size: u64 = 0,
    guest_fds: [16]i32 = .{0} ** 16,
    next_guest_fd: u64 = 3,

    pub fn init(allocator: std.mem.Allocator, binary_data: []const u8) !MachOState {
        var state = try macho.load(allocator, binary_data);
        errdefer state.deinit();

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

        return MachOState{
            .allocator = allocator,
            .mem = mem,
            .mem_base = image_base,
            .mem_size = final_mem_size,
            .data = binary_data,
            .segments = try allocator.dupe(MachSegment, state.segments),
            .entry_point_vaddr = entry_vaddr,
            .stack_size = if (state.stack_size > 0) state.stack_size else STACK_SIZE,
        };
    }

    pub fn deinit(self: *MachOState) void {
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
        const decoded = self.decodeAt() orelse {
            log.err("decode failed at rip=0x{x}", .{self.regs.rip});
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            log.err("invalid instruction at rip=0x{x}, bytes: {any}", .{ self.regs.rip, self.mem[self.addrToOffset(self.regs.rip) orelse 0..][0..@min(@as(usize, 16), self.mem.len - (self.addrToOffset(self.regs.rip) orelse 0))] });
            self.faulted = true;
            self.exit_code = 127;
            self.terminated = true;
            return false;
        }
        log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
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
            self.terminated = true;
        }
    }

    pub fn execute(self: *MachOState, d: DecodedInsn) void {
        switch (d.op) {
            .invalid => unreachable,
            .nop => {},

            .mov_reg8_mem8 => { self.setReg(d.dst_reg, .bits8, self.readMemVal(d.addr, .bits8)); },
            .mov_reg16_mem16 => { self.setReg(d.dst_reg, .bits16, self.readMemVal(d.addr, .bits16)); },
            .mov_reg32_mem32 => { self.setReg(d.dst_reg, .bits32, self.readMemVal(d.addr, .bits32)); },
            .mov_reg64_mem64 => { self.setReg(d.dst_reg, .bits64, self.readMemVal(d.addr, .bits64)); },

            .mov_mem8_reg8 => { self.writeMemVal(d.addr, .bits8, self.regVal(d.src_reg, .bits8)); },
            .mov_mem16_reg16 => { self.writeMemVal(d.addr, .bits16, self.regVal(d.src_reg, .bits16)); },
            .mov_mem32_reg32 => { self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32)); },
            .mov_mem64_reg64 => { self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64)); },

            .mov_reg_imm => { self.setReg(d.dst_reg, d.size, d.imm); },

            .mov_mem8_imm8 => { self.writeMemVal(d.addr, .bits8, d.imm); },
            .mov_mem16_imm16 => { self.writeMemVal(d.addr, .bits16, d.imm); },
            .mov_mem32_imm32 => { self.writeMemVal(d.addr, .bits32, d.imm); },
            .mov_mem64_imm32 => { self.writeMemVal(d.addr, .bits64, d.imm); },

            .mov_reg8_reg8 => { self.setReg(d.dst_reg, .bits8, self.regVal(d.src_reg, .bits8)); },
            .mov_reg16_reg16 => { self.setReg(d.dst_reg, .bits16, self.regVal(d.src_reg, .bits16)); },
            .mov_reg32_reg32 => { self.setReg(d.dst_reg, .bits32, self.regVal(d.src_reg, .bits32)); },
            .mov_reg64_reg64 => { self.setReg(d.dst_reg, .bits64, self.regVal(d.src_reg, .bits64)); },

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
            .and_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a & b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
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
            .xor_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a ^ b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsLogic(r, .bits8);
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

            .push_reg => { self.push(self.regVal(d.dst_reg, .bits64)); },
            .push_mem64 => { self.push(self.readMemVal(d.addr, .bits64)); },
            .push_imm => { self.push(d.imm); },

            .pop_reg => { self.setReg(d.dst_reg, .bits64, self.pop()); },
            .pop_mem64 => { self.writeMemVal(d.addr, .bits64, self.pop()); },

            .call_rel32 => {
                const target = d.addr;
                self.push(self.regs.rip);
                self.regs.rip = target;
            },
            .call_reg64 => {
                const target = self.regVal(d.dst_reg, .bits64);
                self.push(self.regs.rip);
                self.regs.rip = target;
            },
            .call_mem64 => {
                const target = self.readMemVal(d.addr, .bits64);
                self.push(self.regs.rip);
                self.regs.rip = target;
            },

            .ret => {
                if (d.imm > 0) {
                    self.regs.rsp +|= d.imm;
                }
                const ret_addr = self.pop();
                if (ret_addr == 0) {
                    self.terminated = true;
                    self.exit_code = self.regs.rax;
                    return;
                }
                self.regs.rip = ret_addr;
            },

            .jmp_rel8, .jmp_reg64 => {
                self.regs.rip = d.addr;
            },
            .jmp_mem64 => {
                self.regs.rip = self.readMemVal(d.addr, .bits64);
            },

            .jcc_rel8, .jcc_rel32 => {
                const condMet = x64_decoder.evalCond(self.regs.rflags, d.cond);
                if (condMet) self.regs.rip = d.addr;
            },

            .shl_reg_cl, .shl_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
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
                const val = self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .movzx_reg32_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .movsx_reg32_mem8 => {
                const val = self.readMemVal(d.addr, .bits8);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits32, signed_val);
            },
            .movsx_reg32_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits32, signed_val);
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
                    self.regs.rdi, self.regs.rsi, self.regs.rdx,
                    self.regs.r10, self.regs.r8, self.regs.r9,
                );
            },

            .hlt => {
                self.terminated = true;
                self.exit_code = self.regs.rax;
            },

            else => {
                log.warn("unimplemented instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
                self.faulted = true;
                self.exit_code = 127;
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
            arg1, arg2, arg3, arg4, arg5, arg6,
        });

        switch (number) {
            @intFromEnum(macho_runtime.Syscall.exit) => {
                const exit_code = arg1;
                log.info("exit({d})", .{exit_code});
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
            0x66 => { has_66 = true; pos += 1; },
            0x67 => { pos += 1; },
            0xF0 => { has_f0 = true; pos += 1; },
            0xF2 => { has_f2 = true; pos += 1; },
            0xF3 => { has_f3 = true; pos += 1; },
            0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F => {
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
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x14 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .adc_reg8_imm8;
            d.dst_reg = mapReg(2, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x1C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sbb_reg8_imm8;
            d.dst_reg = mapReg(3, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x24 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .and_reg8_imm8;
            d.dst_reg = mapReg(4, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x2C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sub_reg8_imm8;
            d.dst_reg = mapReg(5, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x34 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .xor_reg8_imm8;
            d.dst_reg = mapReg(6, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x3C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .cmp_reg8_imm8;
            d.dst_reg = mapReg(7, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
        },
        0x04 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .add_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.imm = bytes[pos + 1];
            d.len = 2;
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

    if (opcode2 >= 0x84 and opcode2 <= 0x8F) {
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
        return decodeSetcc(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xA2) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0xAF) {
        return decodeImulTwoOp(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB0 or opcode2 == 0xB1) {
        return decodeCmpxchg(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB6 or opcode2 == 0xB7) {
        return decodeMovzx(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xBE or opcode2 == 0xBF) {
        return decodeMovsx(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xC1) {
        return decodeXadd(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0x10 or opcode2 == 0x11) {
        return decodeMovupsMovss(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x28 or opcode2 == 0x29) {
        return decodeMovaps(bytes, pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
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

    d.op = .invalid;
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
    d.op = .invalid;
    d.len = @as(u8, @intCast(pos.* + 1));
    return d;
}

fn decodeSseBytes(_: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, sse_op: anytype) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    _ = pos.*;
    _ = opcode;
    _ = sse_op;
    _ = rex_r;
    _ = rex_x;
    _ = rex_b;
    var d = DecodedInsn{};
    d.op = .invalid;
    return d;
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

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
    const is_reg_reg = bytes[start_pos + 1] >= 0xC0;
    const is_mem_to_reg = (opcode & 0x02) != 0;

    const op_map: [8]Op = .{
        .add_reg8_mem8, .or_reg8_mem8, .adc_reg8_mem8, .sbb_reg8_mem8,
        .and_reg8_mem8, .sub_reg8_mem8, .xor_reg8_mem8, .cmp_reg8_mem8,
    };
    const op_map_rev: [8]Op = .{
        .add_mem8_reg8, .or_mem8_reg8, .invalid, .invalid,
        .and_mem8_reg8, .invalid, .invalid, .cmp_mem8_reg8,
    };

    if (is_reg_reg or is_mem_to_reg) {
        const base_op = op_map[@intFromEnum(arith_type)];
        const off = @intFromEnum(sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base_op) + off);
    } else {
        const base_op = op_map_rev[@intFromEnum(arith_type)];
        const off = @intFromEnum(sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base_op) + off);
    }

    if (is_reg_reg) {
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    } else {
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    }
    d.len = @as(u8, @intCast(pos));

    if (d.op == .invalid) d.op = .invalid;
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
        .add_reg8_imm8, .or_reg8_imm8, .adc_reg8_imm8, .sbb_reg8_imm8,
        .and_reg8_imm8, .sub_reg8_imm8, .xor_reg8_imm8, .cmp_reg8_imm8,
    };

    if (is_mem) {
        const mem_group_ops: [8]Op = .{
            .add_mem8_imm8, .invalid, .invalid, .invalid,
            .invalid, .invalid, .invalid, .cmp_mem8_imm8,
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
        d.op = switch (sz) { .bits8 => .test_mem8_reg8, .bits16 => .test_mem16_reg16, .bits32 => .test_mem32_reg32, .bits64 => .test_mem64_reg64 };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) { .bits8 => .test_reg8_reg8, .bits16 => .test_reg16_reg16, .bits32 => .test_reg32_reg32, .bits64 => .test_reg64_reg64 };
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
        d.op = switch (sz) { .bits32 => .xchg_mem32_reg32, .bits64 => .xchg_mem64_reg64, else => .invalid };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) { .bits32 => .xchg_mem32_reg32, .bits64 => .xchg_mem64_reg64, else => .invalid };
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
        d.op = switch (sz) { .bits32 => .imul_reg32_mem32_imm8, .bits64 => .imul_reg64_mem64_imm8, else => .imul_reg32_mem32_imm8 };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) { .bits32 => .imul_reg32_reg32_imm8, .bits64 => .imul_reg64_reg64_imm8, else => .imul_reg32_reg32_imm8 };
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
        d.op = switch (sz) { .bits32 => .imul_reg32_mem32, .bits64 => .imul_reg64_mem64, else => .imul_reg32_mem32 };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) { .bits32 => .imul_reg32_reg32, .bits64 => .imul_reg64_reg64, else => .imul_reg32_reg32 };
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
        d.op = switch (sz) { .bits32 => .cmpxchg_mem32_reg32, .bits64 => .cmpxchg_mem64_reg64, else => .cmpxchg_mem32_reg32 };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) { .bits32 => .cmpxchg_mem32_reg32, .bits64 => .cmpxchg_mem64_reg64, else => .cmpxchg_mem32_reg32 };
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
        d.addr = rm.addr;
    }

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
        d.addr = rm.addr;
    }

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
        d.op = switch (sz) { .bits32 => .xadd_mem32_reg32, .bits64 => .xadd_mem64_reg64, else => .xadd_mem32_reg32 };
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
