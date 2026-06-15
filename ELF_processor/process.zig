const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.elf);
const elf_loader = @import("elf_loader.zig");
const result_dump = @import("result_dump.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const x64_syscalls = @import("x64_syscalls");

const SYS_exit = x64_syscalls.SYS_exit;
const SYS_write = x64_syscalls.SYS_write;

// ─── RFLAGS bit positions ───
const RFL_CF = x64_decoder.RFL_CF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;

const STACK_SIZE: u64 = 1024 * 1024; // 1 MB stack
const MEM_SIZE: u64 = 64 * 1024 * 1024; // 64 MB total address space
const MEM_BASE: u64 = 0x1000000;

// ─── Shared x64 execution types ───

pub const ElfRegs = x64_decoder.Regs;
pub const Size = x64_decoder.OperandSize;
pub const RegId = x64_decoder.RegId;
pub const Cond = x64_decoder.Condition;
pub const Op = x64_decoder.Op;
pub const DecodedInsn = x64_decoder.DecodedInsn;

// ─── ELF state ───

pub const ElfState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    regs: ElfRegs = .{},
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,

    pub fn init(allocator: std.mem.Allocator) ElfState {
        const mem = allocator.alloc(u8, MEM_SIZE) catch unreachable;
        @memset(mem, 0);
        return .{
            .allocator = allocator,
            .mem = mem,
            .mem_base = MEM_BASE,
            .mem_size = MEM_SIZE,
        };
    }

    pub fn deinit(self: *ElfState) void {
        self.allocator.free(self.mem);
    }

    pub fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    pub fn read8(self: *const ElfState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const ElfState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const ElfState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const ElfState, vaddr: u64) u64 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 8 > self.mem.len) return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
    }

    fn write8(self: *ElfState, vaddr: u64, val: u8) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off < self.mem.len) self.mem[off] = val;
    }

    fn write16(self: *ElfState, vaddr: u64, val: u16) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 2 <= self.mem.len) std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
    }

    fn write32(self: *ElfState, vaddr: u64, val: u32) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 4 <= self.mem.len) std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
    }

    fn write64(self: *ElfState, vaddr: u64, val: u64) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 8 <= self.mem.len) std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
    }

    fn push(self: *ElfState, val: u64) void {
        self.regs.rsp -|= 8;
        self.write64(self.regs.rsp, val);
    }

    fn pop(self: *ElfState) u64 {
        const val = self.read64(self.regs.rsp);
        self.regs.rsp +|= 8;
        return val;
    }

    pub fn loadElf(self: *ElfState, elf_bytes: []const u8) !void {
        self.regs.rip = try elf_loader.loadExecutableSegments(self.mem_base, self.mem, elf_bytes);
    }

    fn sibAddr(self: *const ElfState, d: *DecodedInsn) void {
        if (!d.sib_has_index) return;
        const scale: u3 = @as(u3, d.sib_scale);
        const index_val = self.regVal(d.sib_index_reg, .bits64);
        d.addr +|= index_val << @as(u6, scale);
    }

    fn decodeAt(self: *ElfState) ?DecodedInsn {
        const off = self.addrToOffset(self.regs.rip) orelse return null;
        const remaining = self.mem.len - off;
        if (remaining == 0) return null;
        const bytes = self.mem[off..];
        var d = decodeInsn(bytes);
        // Detect address-size override (0x67) prefix in the raw instruction
        for (bytes[0..@min(@as(usize, @intCast(d.len)), bytes.len)]) |b| {
            if (b == 0x67) {
                d.has_0x67 = true;
                break;
            }
            if (b != 0x66 and !hasRexPrefix(b)) break;
        }
        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        if (d.sib_has_index) {
            const scale: u3 = @as(u3, d.sib_scale);
            const index_val = self.regVal(d.sib_index_reg, addr_size);
            d.addr +|= index_val << @as(u6, scale);
        }
        if (d.sib_has_base) {
            const base_val = self.regVal(d.sib_base_reg, addr_size);
            d.addr +|= base_val;
        }
        return d;
    }

    fn step(self: *ElfState) bool {
        const decoded = self.decodeAt() orelse {
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            log.err("invalid instruction at rip=0x{x}", .{self.regs.rip});
            self.faulted = true;
            self.exit_code = 127;
            self.terminated = true;
            return false;
        }
        x64_interpreter.execute(self, decoded);
        return !self.terminated;
    }

    pub fn run(self: *ElfState) void {
        var steps: u64 = 0;
        const max_steps: u64 = 2_000_000;
        while (!self.terminated and steps < max_steps) : (steps += 1) {
            if (steps % 100000 == 0) {
                log.info("step {d}: rip=0x{x}, rax=0x{x}, rbx=0x{x}, rcx=0x{x}, rsi=0x{x}, rdi=0x{x}", .{ steps, self.regs.rip, self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rsi, self.regs.rdi });
            }
            if (!self.step()) break;
        }
        if (steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.logRegs();
            self.faulted = true;
            self.exit_code = 124;
            self.terminated = true;
        }
    }

    fn logRegs(self: *ElfState) void {
        log.info("  regs: rax=0x{x} rbx=0x{x} rcx=0x{x} rdx=0x{x} rsi=0x{x} rdi=0x{x} rsp=0x{x} rbp=0x{x} rip=0x{x}", .{
            self.regs.rax, self.regs.rbx, self.regs.rcx, self.regs.rdx,
            self.regs.rsi, self.regs.rdi, self.regs.rsp, self.regs.rbp,
            self.regs.rip,
        });
        log.info("  flags: cf={d} zf={d} sf={d} of={d}", .{
            @as(u1, @truncate(self.regs.rflags >> 0)),
            @as(u1, @truncate(self.regs.rflags >> 6)),
            @as(u1, @truncate(self.regs.rflags >> 7)),
            @as(u1, @truncate(self.regs.rflags >> 11)),
        });
    }

    fn regVal(self: *ElfState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn readMemVal(self: *ElfState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    fn writeMemVal(self: *ElfState, addr: u64, size: Size, val: u64) void {
        switch (size) {
            .bits8 => self.write8(addr, @intCast(val & 0xFF)),
            .bits16 => self.write16(addr, @intCast(val & 0xFFFF)),
            .bits32 => self.write32(addr, @intCast(val & 0xFFFFFFFF)),
            .bits64 => self.write64(addr, val),
        }
    }

    fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn evalCond(rflags: u32, cond: Cond) bool {
        return x64_decoder.evalCond(rflags, cond);
    }

    pub fn execute(self: *ElfState, d: DecodedInsn) void {
        switch (d.op) {
            .invalid => unreachable,

            // ── mov reg, mem ──
            .mov_reg8_mem8 => {
                const val = self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, .bits8, val);
            },
            .mov_reg16_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_mem64 => {
                const val = self.readMemVal(d.addr, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── mov mem, reg ──
            .mov_mem8_reg8 => {
                const val = self.regVal(d.src_reg, .bits8);
                self.writeMemVal(d.addr, .bits8, val);
            },
            .mov_mem16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.writeMemVal(d.addr, .bits16, val);
            },
            .mov_mem32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, val);
            },
            .mov_mem64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, val);
            },

            // ── mov reg, imm ──
            .mov_reg_imm => {
                self.setReg(d.dst_reg, d.size, d.imm);
            },

            // ── mov mem, imm ──
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            // ── mov reg64, reg64 ──
            .mov_reg8_reg8 => {
                const val = self.regVal(d.src_reg, .bits8);
                self.setReg(d.dst_reg, .bits8, val);
            },
            .mov_reg16_reg16 => {
                const val = self.regVal(d.src_reg, .bits16);
                self.setReg(d.dst_reg, .bits16, val);
            },
            .mov_reg32_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .mov_reg64_reg64 => {
                const val = self.regVal(d.src_reg, .bits64);
                self.setReg(d.dst_reg, .bits64, val);
            },

            // ── add reg, mem (d=1) ──
            .add_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },

            // ── add r/m, reg (d=0) ──
            .add_mem8_reg8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_mem16_reg16 => {
                const a = self.readMemVal(d.addr, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a +% b;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },

            // ── add reg, reg ──
            .add_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b, r, .bits8);
            },
            .add_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsAdd(a, b, r, .bits16);
            },
            .add_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsAdd(a, b, r, .bits32);
            },
            .add_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a +% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsAdd(a, b, r, .bits64);
            },

            // ── sub reg, mem ──
            .sub_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b, r, .bits8);
            },
            .sub_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, b, r, .bits16);
            },
            .sub_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, b, r, .bits32);
            },
            .sub_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, b, r, .bits64);
            },

            // ── sub reg, reg ──
            .sub_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b, r, .bits8);
            },
            .sub_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, b, r, .bits16);
            },
            .sub_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, b, r, .bits32);
            },
            .sub_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = a -% b;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, b, r, .bits64);
            },

            // ── sub r/m8, imm8 (0x80 /5) ──
            .sub_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const r = a -% d.imm;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, d.imm, r, .bits8);
            },
            .sub_reg16_imm8 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsSub(a, imm, r, .bits16);
            },
            .sub_reg32_imm8 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsSub(a, imm, r, .bits32);
            },
            .sub_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const imm = signExtendImm8(d.imm);
                const r = a -% imm;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsSub(a, imm, r, .bits64);
            },
            .sub_mem8_imm8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const r = a -% d.imm;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsSub(a, d.imm, r, .bits8);
            },

            // ── cmp r/m, reg (opcode 0x39) ──
            .cmp_mem8_reg8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_mem16_reg16 => {
                const a = self.readMemVal(d.addr, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp reg, reg (opcode 0x39, mod=3) ──
            .cmp_reg8_reg8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.regVal(d.src_reg, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_reg16_reg16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.regVal(d.src_reg, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp reg, r/m (0x3A/0x3B, d=1) ──
            .cmp_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                self.setFlagsSub(a, b, a -% b, .bits8);
            },
            .cmp_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                self.setFlagsSub(a, b, a -% b, .bits16);
            },
            .cmp_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                self.setFlagsSub(a, b, a -% b, .bits32);
            },
            .cmp_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                self.setFlagsSub(a, b, a -% b, .bits64);
            },

            // ── cmp r/m, imm8 (0x83 /7) ──
            .cmp_mem8_imm8 => {
                const a = self.readMemVal(d.addr, .bits8);
                const imm = d.imm & 0xFF;
                self.setFlagsSub(a, imm, a -% imm, .bits8);
            },
            .cmp_mem16_imm8 => {
                const a = self.readMemVal(d.addr, .bits16);
                const imm_sext = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u16, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits16);
            },
            .cmp_mem32_imm8 => {
                const a = self.readMemVal(d.addr, .bits32);
                const imm_sext = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u32, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits32);
            },
            .cmp_mem64_imm8 => {
                const a = self.readMemVal(d.addr, .bits64);
                const imm_sext = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u64, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits64);
            },
            .cmp_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const imm = d.imm & 0xFF;
                self.setFlagsSub(a, imm, a -% imm, .bits8);
            },
            .cmp_reg16_imm8 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const imm_sext = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u16, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits16);
            },
            .cmp_reg32_imm8 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const imm_sext = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u32, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits32);
            },
            .cmp_reg64_imm8 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const imm_sext = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const imm = @as(u64, @bitCast(imm_sext));
                self.setFlagsSub(a, imm, a -% imm, .bits64);
            },

            // ── inc/dec memory ──
            .inc_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old +% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_mem8 => {
                const old = self.readMemVal(d.addr, .bits8);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_mem16 => {
                const old = self.readMemVal(d.addr, .bits16);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_mem32 => {
                const old = self.readMemVal(d.addr, .bits32);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_mem64 => {
                const old = self.readMemVal(d.addr, .bits64);
                const r = old -% 1;
                self.writeMemVal(d.addr, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── inc/dec register (0xFF /0, /1 with mod=3) ──
            .inc_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, true);
            },
            .inc_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, true);
            },
            .inc_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, true);
            },
            .inc_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old +% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, true);
            },
            .dec_reg8 => {
                const old = self.regVal(d.dst_reg, .bits8);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsIncDec(old, r, .bits8, false);
            },
            .dec_reg16 => {
                const old = self.regVal(d.dst_reg, .bits16);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits16, r);
                self.setFlagsIncDec(old, r, .bits16, false);
            },
            .dec_reg32 => {
                const old = self.regVal(d.dst_reg, .bits32);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits32, r);
                self.setFlagsIncDec(old, r, .bits32, false);
            },
            .dec_reg64 => {
                const old = self.regVal(d.dst_reg, .bits64);
                const r = old -% 1;
                self.setReg(d.dst_reg, .bits64, r);
                self.setFlagsIncDec(old, r, .bits64, false);
            },

            // ── mul [mem] (unsigned, accumulator form) ──
            .mul_mem8 => {
                const b = self.readMemVal(d.addr, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_mem16 => {
                const b: u16 = @intCast(self.readMemVal(d.addr, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_mem32 => {
                const b = self.readMemVal(d.addr, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_mem64 => {
                const b = self.readMemVal(d.addr, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result: u128 = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul [mem] (signed, accumulator form) ──
            .imul_mem8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_mem16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                const ru: u32 = @bitCast(result);
                const lo: u16 = @truncate(ru);
                const hi: u16 = @truncate(ru >> 16);
                self.setReg(.al_ax_eax_rax, .bits16, lo);
                self.setReg(.dl_dx_edx_rdx, .bits16, hi);
            },
            .imul_mem32 => {
                const a: i32 = @bitCast(@as(u32, @intCast(self.regVal(.al_ax_eax_rax, .bits32))));
                const b: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                const lo: u32 = @truncate(ru);
                const hi: u32 = @truncate(ru >> 32);
                self.setReg(.al_ax_eax_rax, .bits32, lo);
                self.setReg(.dl_dx_edx_rdx, .bits32, hi);
            },
            .imul_mem64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                const lo: u64 = @truncate(ru);
                const hi: u64 = @truncate(ru >> 64);
                self.setReg(.al_ax_eax_rax, .bits64, lo);
                self.setReg(.dl_dx_edx_rdx, .bits64, hi);
            },

            // ── div [mem] (unsigned) ──
            .div_mem8 => {
                const divisor = self.readMemVal(d.addr, .bits8);
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_mem16 => {
                const divisor = self.readMemVal(d.addr, .bits16);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_mem32 => {
                const divisor = self.readMemVal(d.addr, .bits32);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_mem64 => {
                const divisor = self.readMemVal(d.addr, .bits64);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv [mem] (signed) ──
            .idiv_mem8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.readMemVal(d.addr, .bits8))));
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_mem16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.readMemVal(d.addr, .bits16))));
                if (divisor == 0) return;
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_mem32 => {
                const divisor: i32 = @bitCast(@as(u32, @intCast(self.readMemVal(d.addr, .bits32))));
                if (divisor == 0) return;
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_mem64 => {
                const divisor: i64 = @bitCast(self.readMemVal(d.addr, .bits64));
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64);
            },

            // ── mul reg (unsigned) ──
            .mul_reg8 => {
                const b = self.regVal(d.src_reg, .bits8);
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const result = @as(u16, @intCast(a)) * @as(u16, @intCast(b));
                self.setReg(.al_ax_eax_rax, .bits16, result);
            },
            .mul_reg16 => {
                const b: u16 = @intCast(self.regVal(d.src_reg, .bits16));
                const a: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const result: u32 = @as(u32, a) * @as(u32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(result & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast((result >> 16) & 0xFFFF));
            },
            .mul_reg32 => {
                const b = self.regVal(d.src_reg, .bits32);
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const result = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(result & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast((result >> 32) & 0xFFFFFFFF));
            },
            .mul_reg64 => {
                const b = self.regVal(d.src_reg, .bits64);
                const a = self.regVal(.al_ax_eax_rax, .bits64);
                const result = @as(u128, a) * @as(u128, b);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(result & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast((result >> 64) & 0xFFFFFFFFFFFFFFFF));
            },

            // ── imul reg (signed) ──
            .imul_reg8 => {
                const a: i8 = @bitCast(@as(u8, @intCast(self.regVal(.al_ax_eax_rax, .bits8))));
                const b: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                const result: i16 = @as(i16, a) * @as(i16, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(result)));
            },
            .imul_reg16 => {
                const a: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const b: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                const result: i32 = @as(i32, a) * @as(i32, b);
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result)))));
                self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @truncate(result >> 16)))));
            },
            .imul_reg32 => {
                const raw_a: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const raw_b: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const a: i32 = @bitCast(raw_a);
                const b: i32 = @bitCast(raw_b);
                const result: i64 = @as(i64, a) * @as(i64, b);
                const ru: u64 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(ru >> 32));
            },
            .imul_reg64 => {
                const a: i64 = @bitCast(self.regVal(.al_ax_eax_rax, .bits64));
                const b: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                const result: i128 = @as(i128, a) * @as(i128, b);
                const ru: u128 = @bitCast(result);
                self.setReg(.al_ax_eax_rax, .bits64, @truncate(ru));
                self.setReg(.dl_dx_edx_rdx, .bits64, @truncate(ru >> 64));
            },

            // ── div reg (unsigned) ──
            .div_reg8 => {
                const divisor = self.regVal(d.src_reg, .bits8);
                if (divisor == 0) return;
                const dividend = self.regVal(.al_ax_eax_rax, .bits16);
                const quot = dividend / @as(u16, @truncate(divisor));
                const rem = dividend % @as(u16, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @intCast(quot & 0xFF));
                self.setReg(.dl_dx_edx_rdx, .bits8, @intCast(rem & 0xFF));
            },
            .div_reg16 => {
                const divisor = self.regVal(d.src_reg, .bits16);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits16);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits16);
                const dividend = (@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo));
                const quot = dividend / @as(u32, @truncate(divisor));
                const rem = dividend % @as(u32, @truncate(divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @intCast(quot & 0xFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits16, @intCast(rem & 0xFFFF));
            },
            .div_reg32 => {
                const divisor = self.regVal(d.src_reg, .bits32);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits32);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits32);
                const dividend = (@as(u64, dividend_hi) << 32) | dividend_lo;
                const quot = dividend / @as(u64, divisor);
                const rem = dividend % @as(u64, divisor);
                self.setReg(.al_ax_eax_rax, .bits32, @intCast(quot & 0xFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits32, @intCast(rem & 0xFFFFFFFF));
            },
            .div_reg64 => {
                const divisor = self.regVal(d.src_reg, .bits64);
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend = (@as(u128, dividend_hi) << 64) | dividend_lo;
                const quot = dividend / @as(u128, divisor);
                const rem = dividend % @as(u128, divisor);
                self.setReg(.al_ax_eax_rax, .bits64, @intCast(quot & 0xFFFFFFFFFFFFFFFF));
                self.setReg(.dl_dx_edx_rdx, .bits64, @intCast(rem & 0xFFFFFFFFFFFFFFFF));
            },

            // ── idiv reg (signed) ──
            .idiv_reg8 => {
                const divisor: i8 = @bitCast(@as(u8, @intCast(self.regVal(d.src_reg, .bits8))));
                if (divisor == 0) return;
                const dividend: i16 = @bitCast(@as(u16, @intCast(self.regVal(.al_ax_eax_rax, .bits16))));
                const quot = @divTrunc(dividend, @as(i16, divisor));
                const rem = @rem(dividend, @as(i16, divisor));
                self.setReg(.al_ax_eax_rax, .bits8, @as(u8, @bitCast(@as(i8, @truncate(quot)))));
                self.setReg(.dl_dx_edx_rdx, .bits8, @as(u8, @bitCast(@as(i8, @truncate(rem)))));
            },
            .idiv_reg16 => {
                const divisor: i16 = @bitCast(@as(u16, @intCast(self.regVal(d.src_reg, .bits16))));
                if (divisor == 0) return;
                const dividend_lo: u16 = @intCast(self.regVal(.al_ax_eax_rax, .bits16));
                const dividend_hi: u16 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits16));
                const dividend: i32 = @bitCast((@as(u32, @truncate(dividend_hi)) << 16) | @as(u32, @truncate(dividend_lo)));
                const quot = @divTrunc(dividend, @as(i32, divisor));
                const rem = @rem(dividend, @as(i32, divisor));
                {
                    const q: i16 = @truncate(quot);
                    const r: i16 = @truncate(rem);
                    self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(q)));
                    self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(r)));
                }
            },
            .idiv_reg32 => {
                const divisor_raw: u32 = @intCast(self.regVal(d.src_reg, .bits32));
                const divisor: i32 = @bitCast(divisor_raw);
                if (divisor == 0) return;
                const dividend_lo: u32 = @intCast(self.regVal(.al_ax_eax_rax, .bits32));
                const dividend_hi: u32 = @intCast(self.regVal(.dl_dx_edx_rdx, .bits32));
                const dividend: i64 = @bitCast((@as(u64, dividend_hi) << 32) | @as(u64, dividend_lo));
                const quot = @divTrunc(dividend, @as(i64, divisor));
                const rem = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u64, @bitCast(quot)));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u64, @bitCast(rem)));
            },
            .idiv_reg64 => {
                const divisor: i64 = @bitCast(self.regVal(d.src_reg, .bits64));
                if (divisor == 0) return;
                const dividend_lo = self.regVal(.al_ax_eax_rax, .bits64);
                const dividend_hi = self.regVal(.dl_dx_edx_rdx, .bits64);
                const dividend: i128 = @bitCast((@as(u128, dividend_hi) << 64) | dividend_lo);
                const quot = @divTrunc(dividend, @as(i128, divisor));
                const rem = @rem(dividend, @as(i128, divisor));
                const q64b: u64 = @bitCast(@as(i64, @truncate(quot)));
                const r64b: u64 = @bitCast(@as(i64, @truncate(rem)));
                self.setReg(.al_ax_eax_rax, .bits64, q64b);
                self.setReg(.dl_dx_edx_rdx, .bits64, r64b);
            },

            // ── Sign extension ──
            .cbw => {
                // cbw: AL → AX (sign extend). With 0x66: AX → EAX. With REX.W: EAX → RAX (cdqe)
                const al = self.regVal(.al_ax_eax_rax, .bits8);
                const extended = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(al)))));
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(extended)));
            },
            .cwde => {
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const extended = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(ax)))));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(extended)));
            },
            .cdqe => {
                const eax = self.regVal(.al_ax_eax_rax, .bits32);
                const extended = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(eax)))));
                self.setReg(.al_ax_eax_rax, .bits64, @as(u64, @bitCast(extended)));
            },
            .cwd => {
                // cwd: AX → DX:AX. With 0x66: EAX → EDX:EAX (cdq). With REX.W: RAX → RDX:RAX (cqo)
                const ax = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = if (ax & 0x8000 != 0) @as(u16, 0xFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits16, sign);
            },
            .cdq => {
                // cdq: EAX → EDX:EAX (sign extend eax into edx)
                const eax32 = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = if (eax32 & 0x80000000 != 0) @as(u32, 0xFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits32, sign);
            },
            .cqo => {
                // cqo: RAX → RDX:RAX (sign extend rax into rdx)
                const rax = self.regVal(.al_ax_eax_rax, .bits64);
                const sign = if (rax & 0x8000000000000000 != 0) @as(u64, 0xFFFFFFFFFFFFFFFF) else 0;
                self.setReg(.dl_dx_edx_rdx, .bits64, sign);
            },

            // ── Zero/sign extend loads ──
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
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.regVal(d.src_reg, .bits8))))))
                else
                    @as(i64, @as(i8, @bitCast(@as(u8, @truncate(self.readMemVal(d.addr, .bits8))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.regVal(d.src_reg, .bits16))))))
                else
                    @as(i64, @as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))));
                const dst_size: Size = if (d.size == .bits64) .bits64 else .bits32;
                self.setReg(d.dst_reg, dst_size, @as(u64, @bitCast(val)));
            },
            .movsxd_reg64_reg32 => {
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regVal(d.src_reg, .bits32))))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
            },

            // ── imul r64, r/m64 (0F AF) ──
            .imul_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                const r = @as(i64, @bitCast(a)) * @as(i64, @bitCast(b));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                const r = @as(i32, @bitCast(@as(u32, @truncate(a)))) * @as(i32, @bitCast(@as(u32, @truncate(b))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── imul r, r/m, imm8 (0x6B) ──
            .imul_reg64_mem64_imm8 => {
                const b = self.readMemVal(d.addr, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg64_reg64_imm8 => {
                const b = self.regVal(d.src_reg, .bits64);
                const imm = @as(i64, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i64, @bitCast(b)) * imm;
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(r)));
            },
            .imul_reg32_mem32_imm8 => {
                const b = self.readMemVal(d.addr, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },
            .imul_reg32_reg32_imm8 => {
                const b = self.regVal(d.src_reg, .bits32);
                const imm = @as(i32, @as(i8, @bitCast(@as(u8, @truncate(d.imm)))));
                const r = @as(i32, @bitCast(@as(u32, @truncate(b)))) * imm;
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(r)));
            },

            // ── Stack and calls ──
            .call_rel32 => {
                const next_rip = self.regs.rip + d.len;
                const rel = @as(i64, @bitCast(d.imm));
                const target = @as(i64, @bitCast(self.regs.rip)) + @as(i64, d.len) + rel;
                self.push(next_rip);
                self.regs.rip = @as(u64, @bitCast(target));
                return;
            },
            .ret => {
                self.regs.rip = self.pop();
                return;
            },
            .push_reg => {
                self.push(self.regVal(d.src_reg, .bits64));
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
                const val = self.pop();
                self.writeMemVal(d.addr, .bits64, val);
            },

            // ── Jump short rel8 ──
            .jmp_rel8 => {
                const target = @as(i64, @bitCast(self.regs.rip)) + d.len + @as(i64, @bitCast(d.imm));
                self.regs.rip = @as(u64, @bitCast(target));
                return;
            },

            // ── Conditional jump rel8 ──
            .jcc_rel8 => {
                if (evalCond(self.regs.rflags, d.cond)) {
                    const target = @as(i64, @bitCast(self.regs.rip)) + d.len + @as(i64, @bitCast(d.imm));
                    self.regs.rip = @as(u64, @bitCast(target));
                    return;
                }
            },

            // ── Syscall ──
            .syscall => {
                switch (self.regs.rax) {
                    SYS_exit => {
                        self.exit_code = self.regs.rdi;
                        self.terminated = true;
                    },
                    SYS_write => {
                        self.handleWriteSyscall();
                    },
                    else => {
                        log.warn("unimplemented syscall {d}", .{self.regs.rax});
                        self.faulted = true;
                        self.exit_code = 127;
                        self.terminated = true;
                    },
                }
            },

            else => unreachable,
        }

        if (!self.terminated) {
            self.regs.rip += d.len;
        }
    }

    fn handleWriteSyscall(self: *ElfState) void {
        const fd = self.regs.rdi;
        const addr = self.regs.rsi;
        const count = self.regs.rdx;
        const off = self.addrToOffset(addr) orelse {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        };
        if (count > std.math.maxInt(usize)) {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) {
            self.regs.rax = x64_syscalls.errnoValue(.bad_address);
            return;
        }

        const data = self.mem[off_usize .. off_usize + count_usize];
        if (fd == 1) {
            x64_syscalls.writeHostAll(std.posix.STDOUT_FILENO, data) catch {
                self.regs.rax = x64_syscalls.errnoValue(.io);
                return;
            };
            self.regs.rax = count;
        } else if (fd == 2) {
            x64_syscalls.writeHostAll(std.posix.STDERR_FILENO, data) catch {
                self.regs.rax = x64_syscalls.errnoValue(.io);
                return;
            };
            self.regs.rax = count;
        } else {
            self.regs.rax = x64_syscalls.errnoValue(.bad_file_descriptor);
        }
    }
};

// ─── Decoder ───

fn hasRexPrefix(byte: u8) bool {
    return byte & 0xF0 == 0x40;
}

fn rexW(rex: u8) bool {
    return rex & 0x08 != 0;
}

fn rexR(rex: u8) bool {
    return rex & 0x04 != 0;
}

fn rexX(rex: u8) bool {
    return rex & 0x02 != 0;
}

fn rexB(rex: u8) bool {
    return rex & 0x01 != 0;
}

fn regId(code: u8, extended: bool) RegId {
    const value: u4 = @as(u4, @truncate(code)) | if (extended) @as(u4, 8) else @as(u4, 0);
    return @enumFromInt(value);
}

fn modRmReg(code: u8, rex: u8) RegId {
    return regId(code, rexR(rex));
}

fn modRmRm(code: u8, rex: u8) RegId {
    return regId(code, rexB(rex));
}

fn signExtendImm8(imm: u64) u64 {
    const signed: i8 = @bitCast(@as(u8, @truncate(imm)));
    return @as(u64, @bitCast(@as(i64, signed)));
}

const MemRef = struct {
    addr: u64,
    sib_has_index: bool,
    sib_index_reg: RegId,
    sib_scale: u2,
    sib_has_base: bool,
    sib_base_reg: RegId,
};

fn parseModRmMemory(bytes: []const u8, pos: *usize, mod: u3, rm: u8, rex: u8) ?MemRef {
    if (rm == 4) return parseSib(bytes, pos, mod, rex);

    var addr: u64 = 0;
    var has_base = true;
    if (mod == 0 and rm == 5) {
        if (pos.* + 4 > bytes.len) return null;
        addr = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
        has_base = false;
    } else if (mod == 1) {
        if (pos.* + 1 > bytes.len) return null;
        addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i8, bytes[pos.*..][0..1], .little))));
        pos.* += 1;
    } else if (mod == 2) {
        if (pos.* + 4 > bytes.len) return null;
        addr = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
    }

    return .{
        .addr = addr,
        .sib_has_index = false,
        .sib_index_reg = .al_ax_eax_rax,
        .sib_scale = 0,
        .sib_has_base = has_base,
        .sib_base_reg = modRmRm(rm, rex),
    };
}

fn parseSib(bytes: []const u8, pos: *usize, mod: u3, rex: u8) ?MemRef {
    if (pos.* >= bytes.len) return null;
    const sib_byte = bytes[pos.*];
    pos.* += 1;
    const base = sib_byte & 7;
    const index = (sib_byte >> 3) & 7;
    const scale: u2 = @as(u2, @truncate(sib_byte >> 6));

    // Absolute disp32: mod=00, base=5, index=4
    if (mod == 0 and base == 5 and index == 4) {
        if (pos.* + 4 > bytes.len) return null;
        const addr = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
        return .{
            .addr = addr,
            .sib_has_index = false,
            .sib_index_reg = .al_ax_eax_rax,
            .sib_scale = 0,
            .sib_has_base = false,
            .sib_base_reg = .al_ax_eax_rax,
        };
    }

    // SIB with register components — read displacement
    var addr: u64 = 0;
    if (mod == 0 and base == 5) {
        // [index*scale + disp32], no base register
        if (pos.* + 4 > bytes.len) return null;
        addr = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
    } else if (mod == 1) {
        if (pos.* + 1 > bytes.len) return null;
        addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i8, bytes[pos.*..][0..1], .little))));
        pos.* += 1;
    } else if (mod == 2) {
        if (pos.* + 4 > bytes.len) return null;
        addr = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
    }

    return .{
        .addr = addr,
        .sib_has_index = (index != 4),
        .sib_index_reg = regId(index, rexX(rex)),
        .sib_scale = scale,
        .sib_has_base = !(mod == 0 and base == 5),
        .sib_base_reg = modRmRm(base, rex),
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};

    var pos: usize = 0;
    var rex: u8 = 0;
    var has_66: bool = false;
    var has_0x67: bool = false;

    // Parse prefixes
    while (pos < bytes.len and pos < 15) {
        const b = bytes[pos];
        if (b == 0x66) {
            has_66 = true;
            pos += 1;
        } else if (b == 0x67) {
            has_0x67 = true;
            pos += 1;
        } else if (hasRexPrefix(b)) {
            rex = b;
            pos += 1;
        } else {
            break;
        }
    }

    if (pos >= bytes.len) return .{};

    const opcode = bytes[pos];
    pos += 1;

    const rex_w = rexW(rex);

    switch (opcode) {
        0x00...0x03 => {
            // ADD r/m, r or ADD r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod != 3 and rm == 4) {
                const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod)), rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 1) {
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    };
                } else {
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .add_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .add_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .add_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .add_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },
        0x28...0x2B => {
            // SUB r/m, r or SUB r, r/m
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib_byte = bytes[pos];
                pos += 1;
                _ = (sib_byte >> 3) & 7;
                const sib_base = sib_byte & 7;
                if (sib_base == 5 and mod == 0 and d == 1) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .sub_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .sub_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .sub_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .sub_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x38...0x3B => {
            // CMP r/m, r (38/39) or CMP r, r/m (3A/3B)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const d = (opcode >> 1) & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v == 3) {
                const dst_reg = if (d == 1) modRmReg(reg, rex) else modRmRm(rm, rex);
                const src_reg = if (d == 1) modRmRm(rm, rex) else modRmReg(reg, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (rm == 4) {
                const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v)), rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 0) {
                    // cmp r/m, r: source is reg, dst is [addr]
                    const src_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    };
                } else {
                    // cmp reg, r/m: dst is reg, source is [addr]
                    const dst_reg = modRmReg(reg, rex);
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    };
                }
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x63 => {
            // MOVSXD r64, r/m32 (only with REX.W)
            if (!rex_w) return .{};
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .movsxd_reg64_reg32,
                    .dst_reg = modRmReg(reg, rex),
                    .src_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }
            return .{};
        },

        0x50...0x57 => {
            // PUSH r64
            return DecodedInsn{
                .op = .push_reg,
                .size = .bits64,
                .src_reg = regId(opcode - 0x50, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x58...0x5F => {
            // POP r64
            return DecodedInsn{
                .op = .pop_reg,
                .size = .bits64,
                .dst_reg = regId(opcode - 0x58, rexB(rex)),
                .len = @intCast(pos),
            };
        },

        0x68 => {
            // PUSH imm32, sign-extended to stack width.
            if (pos + 4 > bytes.len) return .{};
            const imm = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x6B => {
            // IMUL r, r/m, imm8
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const dst_reg = modRmReg(reg, rex);
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            const size: Size = if (rex_w) .bits64 else .bits32;
            if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                const sib_index = (sib >> 3) & 7;
                if (base == 5 and sib_index == 4) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64_imm8, .size = size, .dst_reg = dst_reg, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
            } else if (mod_v == 3) {
                const src_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits32 => DecodedInsn{ .op = .imul_reg32_reg32_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .imul_reg64_reg64_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x6A => {
            // PUSH imm8, sign-extended to stack width.
            if (pos >= bytes.len) return .{};
            const imm = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .push_imm,
                .size = .bits64,
                .imm = @as(u64, @bitCast(@as(i64, imm))),
                .len = @intCast(pos),
            };
        },

        0x70...0x7F => {
            // Conditional jumps
            const cond: Cond = @enumFromInt(@as(u4, @truncate(opcode & 0x0F)));
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jcc_rel8,
                .cond = cond,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0x80 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP r/m8, imm8
            // /5 = SUB, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    5 => DecodedInsn{ .op = .sub_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = .bits8, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                return switch (reg_field) {
                    5 => DecodedInsn{ .op = .sub_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    7 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = .bits8, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x83 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP with imm8 sign-extended
            // /5 = SUB, /7 = CMP
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 5 and reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                const dst_reg = modRmRm(rm, rex);
                return if (reg_field == 5) switch (size) {
                    .bits8 => DecodedInsn{ .op = .sub_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .sub_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .sub_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .sub_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                } else switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (pos >= bytes.len) return .{};
                const imm = bytes[pos];
                pos += 1;
                if (reg_field == 5) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_mem16_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_mem32_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_mem64_imm8, .size = size, .imm = imm, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x88, 0x89 => {
            // MOV r/m, r  (88=byte, 89=dword/qword)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const src_reg = modRmReg(reg, rex);

            if (mod_v == 3) {
                const dst_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x8A, 0x8B => {
            // MOV r, r/m  (8A=byte, 8B=dword/qword)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;
            const dst_reg = modRmReg(reg, rex);

            if (mod_v == 3) {
                const src_reg = modRmRm(rm, rex);
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (mod_v != 3) {
                const sib_info = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x8F => {
            // POP r/m64 (Group 1, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (mod_v == 3) {
                return DecodedInsn{
                    .op = .pop_reg,
                    .size = .bits64,
                    .dst_reg = modRmRm(rm, rex),
                    .len = @intCast(pos),
                };
            }

            const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            return DecodedInsn{ .op = .pop_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
        },

        0x98 => {
            // CBW/CWDE/CDQE
            if (rex_w) {
                // CDQE (RAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdqe, .len = @intCast(pos) };
            } else if (has_66) {
                // CBW (AX = sign-extend AL)
                return DecodedInsn{ .op = .cbw, .len = @intCast(pos) };
            } else {
                // CWDE (EAX = sign-extend AX)
                return DecodedInsn{ .op = .cwde, .len = @intCast(pos) };
            }
        },

        0x99 => {
            // CWD/CDQ/CQO
            if (rex_w) {
                // CQO (RDX:RAX = sign-extend RAX)
                return DecodedInsn{ .op = .cqo, .len = @intCast(pos) };
            } else if (has_66) {
                // CWD (DX:AX = sign-extend AX)
                return DecodedInsn{ .op = .cwd, .len = @intCast(pos) };
            } else {
                // CDQ (EDX:EAX = sign-extend EAX)
                return DecodedInsn{ .op = .cdq, .len = @intCast(pos) };
            }
        },

        0xB0...0xB7 => {
            // MOV r8, imm8
            const reg = regId(opcode - 0xB0, rexB(rex));
            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;
            return DecodedInsn{ .op = .mov_reg_imm, .size = .bits8, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
        },

        0xB8...0xBF => {
            // MOV r, imm32 (with REX.W: imm32 sign-extended)
            const reg_bits = opcode - 0xB8;
            const reg = regId(reg_bits, rexB(rex));
            if (has_66) {
                if (pos + 2 > bytes.len) return .{};
                const imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
                pos += 2;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits16, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            } else if (rex_w) {
                if (pos + 8 > bytes.len) return .{};
                const imm = std.mem.readInt(u64, bytes[pos..][0..8], .little);
                pos += 8;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits64, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            } else {
                if (pos + 4 > bytes.len) return .{};
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits32, .dst_reg = reg, .imm = imm, .len = @intCast(pos) };
            }
        },

        0xC7 => {
            // MOV r/m, imm32 (Group 11, /0)
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;

            if (reg_field != 0) return .{};

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (mod_v == 3) {
                // MOV reg, imm32
                if (pos + 4 > bytes.len) return .{};
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{
                    .op = .mov_reg_imm,
                    .size = size,
                    .dst_reg = modRmRm(rm, rex),
                    .imm = if (size == .bits64) @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(imm))))) else imm,
                    .len = @intCast(pos),
                };
            }

            // Memory form
            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                const imm_len: usize = if (size == .bits16) 2 else 4;
                if (pos + imm_len > bytes.len) return .{};
                const imm = if (size == .bits16)
                    @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
                else
                    @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
                pos += imm_len;
                return switch (size) {
                    .bits16 => DecodedInsn{ .op = .mov_mem16_imm16, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_mem32_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_mem64_imm32, .size = size, .addr = mem.addr, .imm = imm, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xC3 => {
            // RET near
            return DecodedInsn{ .op = .ret, .len = @intCast(pos) };
        },

        0xE8 => {
            // CALL rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .call_rel32,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xE9 => {
            // JMP rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xEB => {
            // JMP short rel8
            if (pos >= bytes.len) return .{};
            const rel = std.mem.readInt(i8, bytes[pos..][0..1], .little);
            pos += 1;
            return DecodedInsn{
                .op = .jmp_rel8,
                .imm = @as(u64, @bitCast(@as(i64, rel))),
                .len = @intCast(pos),
            };
        },

        0xFF => {
            // Group 5: INC / DEC / CALL / CALLF / JMP / JMPF / PUSH
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field == 0 or reg_field == 1) {
                const is_inc = reg_field == 0;
                if (mod_v == 3) {
                    const dst_reg = modRmRm(rm, rex);
                    return if (is_inc) switch (size) {
                        .bits8 => DecodedInsn{ .op = .inc_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .inc_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .inc_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .inc_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    } else switch (size) {
                        .bits8 => DecodedInsn{ .op = .dec_reg8, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .dec_reg16, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .dec_reg32, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .dec_reg64, .size = size, .dst_reg = dst_reg, .len = @intCast(pos) },
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return if (is_inc) switch (size) {
                    .bits8 => DecodedInsn{ .op = .inc_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .inc_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .inc_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .inc_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                } else switch (size) {
                    .bits8 => DecodedInsn{ .op = .dec_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .dec_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .dec_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .dec_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                };
            }

            if (reg_field == 6) {
                if (mod_v == 3) {
                    return DecodedInsn{
                        .op = .push_reg,
                        .size = .bits64,
                        .src_reg = modRmRm(rm, rex),
                        .len = @intCast(pos),
                    };
                }
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return DecodedInsn{ .op = .push_mem64, .size = .bits64, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xF6, 0xF7 => {
            // Group 3: TEST / NOT / NEG / MUL / IMUL / DIV / IDIV
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const w = opcode & 1;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod_v != 3) {
                const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (reg_field) {
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_mem8, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_mem16, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_mem32, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_mem64, .size = size, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            } else {
                // Register form: Group 3 with register operand
                const src_reg = modRmRm(rm, rex);
                return switch (reg_field) {
                    4 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .mul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    5 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .imul_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .imul_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .imul_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    6 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .div_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .div_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .div_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .div_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    7 => switch (size) {
                        .bits8 => DecodedInsn{ .op = .idiv_reg8, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .idiv_reg16, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .idiv_reg32, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .idiv_reg64, .size = size, .src_reg = src_reg, .len = @intCast(pos) },
                    },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
        },

        0x0F => {
            if (pos >= bytes.len) return .{};
            const op2 = bytes[pos];
            pos += 1;

            switch (op2) {
                0x05 => {
                    return DecodedInsn{ .op = .syscall, .len = @intCast(pos) };
                },
                0xAF => {
                    // IMUL r, r/m
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;

                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return switch (size) {
                            .bits32 => DecodedInsn{ .op = .imul_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .imul_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                        };
                    }

                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return switch (size) {
                        .bits32 => DecodedInsn{ .op = .imul_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .imul_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                },
                0xB6 => {
                    // MOVZX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
                },
                0xB7 => {
                    // MOVZX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
                },
                0xBE => {
                    // MOVSX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
                },
                0xBF => {
                    // MOVSX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg = modRmReg(reg, rex);
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg = modRmRm(rm, rex);
                        return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    const mem = parseModRmMemory(bytes, &pos, @as(u3, @truncate(mod_v)), rm, rex) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                    return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = mem.addr, .sib_has_index = mem.sib_has_index, .sib_index_reg = mem.sib_index_reg, .sib_scale = mem.sib_scale, .sib_has_base = mem.sib_has_base, .sib_base_reg = mem.sib_base_reg, .len = @intCast(pos) };
                },
                else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            }
        },

        else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
    }
}

// ─── High-level API ───

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    return loadRunElf(allocator, elf_bytes, .{});
}

pub const ElfRunOptions = struct {
    dump_results: bool = false,
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
};

fn loadRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8, options: ElfRunOptions) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    var result_symbols: std.ArrayList(result_dump.DumpSymbol) = .empty;
    defer result_dump.deinitSymbols(allocator, &result_symbols);
    if (options.dump_results) {
        result_symbols = result_dump.collect(allocator, &state, elf_bytes, options.source_text) catch |err| blk: {
            log.warn("result symbols unavailable: {s}", .{@errorName(err)});
            break :blk .empty;
        };
    }

    state.regs.rsp = MEM_BASE + MEM_SIZE - 8;

    state.run();

    if (options.dump_results) {
        result_dump.dump(allocator, &state, result_symbols.items, .{
            .dump_all_results = options.dump_all_results,
            .source_text = options.source_text,
        }) catch |err| {
            log.warn("result dump skipped: {s}", .{@errorName(err)});
        };
    }

    return state.exit_code;
}

/// CLI entry point: `elf_processor <path-to-elf>`
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        return;
    }

    var arg_index: usize = 1;
    var dump_results = envFlag("ROSETTE_ELF_DUMP_RESULTS");
    var dump_all_results = envFlag("ROSETTE_ELF_DUMP_ALL") or envFlag("ROSETTE_ELF_DUMP_ALL_RESULTS");
    while (arg_index < args.len and std.mem.startsWith(u8, args[arg_index], "--")) : (arg_index += 1) {
        if (std.mem.eql(u8, args[arg_index], "--dump-results")) {
            dump_results = true;
        } else if (std.mem.eql(u8, args[arg_index], "--dump-all-results")) {
            dump_results = true;
            dump_all_results = true;
        } else {
            log.err("unknown option: {s}", .{args[arg_index]});
            std.process.exit(126);
        }
    }
    if (arg_index >= args.len) {
        log.err("usage: elf_processor [--dump-results] [--dump-all-results] <elf-path>", .{});
        std.process.exit(126);
    }
    const elf_path = args[arg_index];

    const elf_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, elf_path, init.arena.allocator(), .unlimited);
    const source_text = if (dump_results)
        try readSiblingAsmSource(init.io, init.arena.allocator(), elf_path)
    else
        null;

    const exit_code = loadRunElf(init.arena.allocator(), elf_bytes, .{
        .dump_results = dump_results,
        .dump_all_results = dump_all_results,
        .source_text = source_text,
    }) catch |err| {
        log.err("failed to run ELF: {s}", .{@errorName(err)});
        std.process.exit(126);
    };

    if (envFlag("ROSETTE_ELF_VERBOSE")) {
        log.info("exit_code={d}", .{exit_code});
    }
    std.process.exit(@as(u8, @truncate(exit_code)));
}

fn envFlag(name: [:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.sliceTo(raw, 0);
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    return true;
}

fn readSiblingAsmSource(io: std.Io, allocator: std.mem.Allocator, elf_path: []const u8) !?[]const u8 {
    const direct = try std.mem.concat(allocator, u8, &.{ elf_path, ".asm" });
    if (std.Io.Dir.cwd().readFileAlloc(io, direct, allocator, .limited(512 * 1024))) |source| return source else |_| {}

    const dir = std.fs.path.dirname(elf_path) orelse ".";
    const base = std.fs.path.basename(elf_path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const stem_path = try std.fs.path.join(allocator, &.{ dir, base[0..dot] });
        const candidate = try std.mem.concat(allocator, u8, &.{ stem_path, ".asm" });
        if (std.Io.Dir.cwd().readFileAlloc(io, candidate, allocator, .limited(512 * 1024))) |source| return source else |_| {}
    }

    return null;
}

// ─── Tests ───

test "decode 0x66 0xB8 (mov ax, imm16)" {
    const bytes = [_]u8{ 0x66, 0xB8, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits16, d.size);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
}

test "decode 0xB8 (mov eax, imm32)" {
    const bytes = [_]u8{ 0xB8, 0x78, 0x56, 0x34, 0x12 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits32, d.size);
    try testing.expectEqual(@as(u64, 0x12345678), d.imm);
}

test "decode 0x48 0xB8 (mov rax, imm64)" {
    const bytes = [_]u8{ 0x48, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(Size.bits64, d.size);
}

test "decode 0x8A 0x04 0x25 <addr> (mov al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x8A, 0x04, 0x25, 0x81, 0x26, 0x01, 0x01 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg8_mem8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(@as(u64, 0x01012681), d.addr);
}

test "decode 0x88 0x04 0x25 <addr> (mov byte [abs], al)" {
    var bytes: [7]u8 = [_]u8{ 0x88, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_mem8_reg8, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.src_reg);
}

test "decode 0x02 0x04 0x25 (add al, byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0x02, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.add_reg8_mem8, d.op);
}

test "decode 0xF6 0x24 0x25 (mul byte [abs])" {
    var bytes: [7]u8 = [_]u8{ 0xF6, 0x24, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_mem8, d.op);
}

test "decode 0xF7 0xE3 (mul ebx)" {
    var bytes: [2]u8 = [_]u8{ 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg32, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.src_reg);
}

test "decode 0x48 0xF7 0xE3 (mul rbx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0xF7, 0xE3 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mul_reg64, d.op);
}

test "decode 0x99 (cdq)" {
    var bytes: [1]u8 = [_]u8{0x99};
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cdq, d.op);
}

test "decode 0x48 0x99 (cqo)" {
    var bytes: [2]u8 = [_]u8{ 0x48, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cqo, d.op);
}

test "decode 0x98 sign-extension variants" {
    try testing.expectEqual(Op.cwde, decodeInsn(&[_]u8{0x98}).op);
    try testing.expectEqual(Op.cbw, decodeInsn(&[_]u8{ 0x66, 0x98 }).op);
    try testing.expectEqual(Op.cdqe, decodeInsn(&[_]u8{ 0x48, 0x98 }).op);
}

test "decode 0x0F 0xB7 (movzx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xB7, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movzx_reg32_mem16, d.op);
}

test "decode 0x0F 0xBF (movsx eax, word [abs])" {
    var bytes: [8]u8 = [_]u8{ 0x0F, 0xBF, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsx_reg32_mem16, d.op);
}

test "decode 0x0F 0x05 (syscall)" {
    var bytes: [2]u8 = [_]u8{ 0x0F, 0x05 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.syscall, d.op);
}

test "decode call ret and extended stack forms" {
    var call_bytes: [5]u8 = [_]u8{ 0xE8, 0x64, 0x01, 0x00, 0x00 };
    var d = decodeInsn(&call_bytes);
    try testing.expectEqual(Op.call_rel32, d.op);
    try testing.expectEqual(@as(u8, 5), d.len);
    try testing.expectEqual(@as(u64, 0x164), d.imm);

    d = decodeInsn(&[_]u8{0xC3});
    try testing.expectEqual(Op.ret, d.op);

    d = decodeInsn(&[_]u8{ 0x41, 0x54 });
    try testing.expectEqual(Op.push_reg, d.op);
    try testing.expectEqual(RegId.r12b_r12w_r12d_r12, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0x5F });
    try testing.expectEqual(Op.pop_reg, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
}

test "decode REX-aware arithmetic and move-extension registers" {
    var d = decodeInsn(&[_]u8{ 0x45, 0x6B, 0xFF, 0x04 });
    try testing.expectEqual(Op.imul_reg32_reg32_imm8, d.op);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.dst_reg);
    try testing.expectEqual(RegId.r15b_r15w_r15d_r15, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x41, 0xF7, 0xFD });
    try testing.expectEqual(Op.idiv_reg32, d.op);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xAF, 0xC5 });
    try testing.expectEqual(Op.imul_reg64_reg64, d.op);
    try testing.expectEqual(RegId.al_ax_eax_rax, d.dst_reg);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.src_reg);

    d = decodeInsn(&[_]u8{ 0x4C, 0x0F, 0xB6, 0xEE });
    try testing.expectEqual(Op.movzx_reg32_mem8, d.op);
    try testing.expectEqual(Size.bits64, d.size);
    try testing.expectEqual(RegId.r13b_r13w_r13d_r13, d.dst_reg);
    try testing.expectEqual(RegId.dh_si_esi_rsi, d.src_reg);
    try testing.expect(d.is_reg_form);
}

test "decode 0x48 0x63 0xDB (movsxd rbx, ebx)" {
    var bytes: [3]u8 = [_]u8{ 0x48, 0x63, 0xDB };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.movsxd_reg64_reg32, d.op);
}

test "decode 0x48 0xC7 0xC3 (mov rbx, imm32)" {
    var bytes: [7]u8 = [_]u8{ 0x48, 0xC7, 0xC3, 0x00, 0x00, 0x00, 0x00 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.mov_reg_imm, d.op);
    try testing.expectEqual(RegId.bl_bx_ebx_rbx, d.dst_reg);
}

test "decode 0x66 0x99 (cwd)" {
    var bytes: [2]u8 = [_]u8{ 0x66, 0x99 };
    const d = decodeInsn(&bytes);
    try testing.expectEqual(Op.cwd, d.op);
}

test "mul byte [mem] and check result" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Place operands: bNum1=34 at vaddr 0x100267c, bNum3=19 at 0x100267e
    state.write8(0x100267c, 34); // bNum1
    state.write8(0x100267e, 19); // bNum3

    // Set RIP and decode "mov al, byte [bNum1]" + "mul byte [bNum3]" + "mov word [result], ax"
    state.regs.rip = 0x1001160;
    state.regs.rax = 0;

    // Manually execute mov al, [bNum1]
    state.regs.rip = 0x1001160;
    var decoded = decodeInsn(&[_]u8{ 0x8A, 0x04, 0x25, 0x7C, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mov_reg8_mem8, decoded.op);
    state.execute(decoded);
    try testing.expectEqual(@as(u64, 34), state.regs.rax & 0xFF);

    // Execute mul byte [bNum3]
    decoded = decodeInsn(&[_]u8{ 0xF6, 0x24, 0x25, 0x7E, 0x26, 0x00, 0x01 });
    try testing.expectEqual(Op.mul_mem8, decoded.op);
    state.execute(decoded);
    // 34 * 19 = 646 = 0x286
    try testing.expectEqual(@as(u64, 0x286), state.regs.rax & 0xFFFF);
}

test "cmp reg32 imm8 treats negative 32-bit values as signed negative" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    state.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, -2588))));
    state.execute(.{
        .op = .cmp_reg32_imm8,
        .dst_reg = .al_ax_eax_rax,
        .imm = 0,
        .len = 3,
    });

    try testing.expect((state.regs.rflags & RFL_SF) != 0);
    try testing.expect((state.regs.rflags & RFL_OF) == 0);
    try testing.expect(ElfState.evalCond(state.regs.rflags, .l));
    try testing.expect(!ElfState.evalCond(state.regs.rflags, .ge));
}
