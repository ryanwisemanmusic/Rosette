const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.elf);

// ─── ELF64 constants ───

const EI_MAG0: u8 = 0;
const EI_MAG1: u8 = 1;
const EI_MAG2: u8 = 2;
const EI_MAG3: u8 = 3;
const EI_CLASS: u8 = 4;
const EI_DATA: u8 = 5;
const EI_VERSION: u8 = 6;

const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const EV_CURRENT: u8 = 1;
const EM_X86_64: u16 = 62;
const ET_EXEC: u16 = 2;

const PT_NULL: u32 = 0;
const PT_LOAD: u32 = 1;
const PT_PHDR: u32 = 6;
const PT_GNU_STACK: u32 = 0x6474e551;

const PF_X: u32 = 1;
const PF_W: u32 = 2;
const PF_R: u32 = 4;

const SYS_exit: u64 = 60;
const SYS_write: u64 = 1;

const STACK_SIZE: u64 = 1024 * 1024; // 1 MB stack
const MEM_SIZE: u64 = 64 * 1024 * 1024; // 64 MB total address space
const MEM_BASE: u64 = 0x1000000;

// ─── ELF64 structures (extern for safe casting) ───

const Elf64_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const Elf64_Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

// ─── Register file ───

pub const ElfRegs = struct {
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rbx: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rip: u64 = 0,
    rflags: u32 = 0x0002,

    pub fn get(self: *const ElfRegs, comptime reg: []const u8) u64 {
        _ = self;
        _ = reg;
        return 0;
    }
};

// ─── Decoded instruction ───

pub const Size = enum(u2) { bits8, bits16, bits32, bits64 };

pub const RegId = enum(u3) {
    al_ax_eax_rax = 0,
    cl_cx_ecx_rcx = 1,
    dl_dx_edx_rdx = 2,
    bl_bx_ebx_rbx = 3,
    ah_sp_esp_rsp = 4,
    ch_bp_ebp_rbp = 5,
    dh_si_esi_rsi = 6,
    bh_di_edi_rdi = 7,

    pub fn highByte(self: RegId) bool {
        return @intFromEnum(self) >= 4;
    }
};

pub const Op = enum(u8) {
    invalid,
    nop,
    // mov
    mov_mem8_reg8,
    mov_mem16_reg16,
    mov_mem32_reg32,
    mov_mem64_reg64,
    mov_reg8_mem8,
    mov_reg16_mem16,
    mov_reg32_mem32,
    mov_reg64_mem64,
    mov_reg_imm,
    // add
    add_reg8_mem8,
    add_reg16_mem16,
    add_reg32_mem32,
    add_reg64_mem64,
    // sub
    sub_reg8_mem8,
    sub_reg16_mem16,
    sub_reg32_mem32,
    sub_reg64_mem64,
    // mul/imul/div/idiv (memory)
    mul_mem8,
    mul_mem16,
    mul_mem32,
    mul_mem64,
    imul_mem8,
    imul_mem16,
    imul_mem32,
    imul_mem64,
    div_mem8,
    div_mem16,
    div_mem32,
    div_mem64,
    idiv_mem8,
    idiv_mem16,
    idiv_mem32,
    idiv_mem64,
    // mul/imul/div/idiv (register)
    mul_reg8,
    mul_reg16,
    mul_reg32,
    mul_reg64,
    imul_reg8,
    imul_reg16,
    imul_reg32,
    imul_reg64,
    div_reg8,
    div_reg16,
    div_reg32,
    div_reg64,
    idiv_reg8,
    idiv_reg16,
    idiv_reg32,
    idiv_reg64,
    // sign extend
    cbw,
    cwd,
    cdq,
    cqo,
    // zero/sign extend loads
    movzx_reg32_mem16,
    movsx_reg32_mem16,
    movsxd_reg64_reg32,
    // syscall
    syscall,
};

pub const DecodedInsn = struct {
    op: Op = .invalid,
    size: Size = .bits32,
    dst_reg: RegId = .al_ax_eax_rax,
    src_reg: RegId = .al_ax_eax_rax,
    addr: u64 = 0,
    imm: u64 = 0,
    len: u8 = 0,
};

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

    fn addrToOffset(self: *const ElfState, vaddr: u64) ?u64 {
        if (vaddr < self.mem_base) return null;
        const off = vaddr - self.mem_base;
        if (off >= self.mem_size) return null;
        return off;
    }

    fn read8(self: *const ElfState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    fn read16(self: *const ElfState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    fn read32(self: *const ElfState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    fn read64(self: *const ElfState, vaddr: u64) u64 {
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
        if (elf_bytes.len < @sizeOf(Elf64_Ehdr)) return error.InvalidElf;
        const ehdr = @as(*const Elf64_Ehdr, @ptrCast(@alignCast(elf_bytes[0..@sizeOf(Elf64_Ehdr)])));

        if (ehdr.e_ident[EI_MAG0] != 0x7f or
            ehdr.e_ident[EI_MAG1] != 'E' or
            ehdr.e_ident[EI_MAG2] != 'L' or
            ehdr.e_ident[EI_MAG3] != 'F') return error.NotElf;
        if (ehdr.e_ident[EI_CLASS] != ELFCLASS64) return error.Not64Bit;
        if (ehdr.e_ident[EI_DATA] != ELFDATA2LSB) return error.NotLittleEndian;
        if (ehdr.e_machine != EM_X86_64) return error.NotX86_64;
        if (ehdr.e_type != ET_EXEC) return error.NotExecutable;

        const phoff = ehdr.e_phoff;
        const phentsize = ehdr.e_phentsize;
        const phnum = ehdr.e_phnum;

        if (phoff == 0 or phentsize < @sizeOf(Elf64_Phdr) or phnum == 0) return error.NoProgramHeaders;
        if (phoff + phnum * phentsize > elf_bytes.len) return error.TruncatedProgramHeaders;

        var i: u16 = 0;
        while (i < phnum) : (i += 1) {
            const phdr_off = phoff + i * phentsize;
            if (phdr_off + @sizeOf(Elf64_Phdr) > elf_bytes.len) return error.TruncatedProgramHeaders;
            const phdr = @as(*const Elf64_Phdr, @ptrCast(@alignCast(elf_bytes[phdr_off..][0..@sizeOf(Elf64_Phdr)])));

            if (phdr.p_type != PT_LOAD) continue;
            if (phdr.p_memsz == 0) continue;

            const vaddr = phdr.p_vaddr;
            const filesz = phdr.p_filesz;
            const memsz = phdr.p_memsz;
            const offset = phdr.p_offset;

            if (offset + filesz > elf_bytes.len) return error.TruncatedSegment;

            const base_off = self.addrToOffset(vaddr) orelse return error.SegmentOutOfRange;
            if (base_off + memsz > self.mem.len) return error.SegmentTooLarge;

            @memcpy(self.mem[base_off..][0..@as(usize, @intCast(filesz))], elf_bytes[offset..][0..@as(usize, @intCast(filesz))]);
        }

        self.regs.rip = ehdr.e_entry;
    }

    fn decodeAt(self: *const ElfState) ?DecodedInsn {
        const off = self.addrToOffset(self.regs.rip) orelse return null;
        const remaining = self.mem.len - off;
        if (remaining == 0) return null;
        const bytes = self.mem[off..];
        return decodeInsn(bytes);
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
        self.execute(decoded);
        return !self.terminated;
    }

    pub fn run(self: *ElfState) void {
        var steps: u64 = 0;
        const max_steps: u64 = 2_000_000;
        while (!self.terminated and steps < max_steps) : (steps += 1) {
            if (!self.step()) break;
        }
        if (steps >= max_steps) {
            log.warn("reached max steps ({d})", .{max_steps});
            self.faulted = true;
            self.exit_code = 124;
            self.terminated = true;
        }
    }

    fn regVal(self: *ElfState, id: RegId, size: Size) u64 {
        const r = @as(u64, @intFromEnum(id));
        const val: u64 = switch (r) {
            0 => self.regs.rax,
            1 => self.regs.rcx,
            2 => self.regs.rdx,
            3 => self.regs.rbx,
            4 => self.regs.rsp,
            5 => self.regs.rbp,
            6 => self.regs.rsi,
            7 => self.regs.rdi,
            else => unreachable,
        };
        return switch (size) {
            .bits8 => if (id.highByte()) (val >> 8) & 0xFF else val & 0xFF,
            .bits16 => val & 0xFFFF,
            .bits32 => val & 0xFFFFFFFF,
            .bits64 => val,
        };
    }

    fn setReg(self: *ElfState, id: RegId, size: Size, val: u64) void {
        const r = @as(u64, @intFromEnum(id));
        const old: u64 = switch (r) {
            0 => self.regs.rax,
            1 => self.regs.rcx,
            2 => self.regs.rdx,
            3 => self.regs.rbx,
            4 => self.regs.rsp,
            5 => self.regs.rbp,
            6 => self.regs.rsi,
            7 => self.regs.rdi,
            else => unreachable,
        };
        const new = switch (size) {
            .bits8 => if (id.highByte()) (old & 0xFFFF_FFFF_FFFF_00FF) | ((val & 0xFF) << 8) else (old & 0xFFFF_FFFF_FFFF_FF00) | (val & 0xFF),
            .bits16 => (old & 0xFFFF_FFFF_FFFF_0000) | (val & 0xFFFF),
            .bits32 => val & 0xFFFFFFFF,
            .bits64 => val,
        };
        switch (r) {
            0 => self.regs.rax = new,
            1 => self.regs.rcx = new,
            2 => self.regs.rdx = new,
            3 => self.regs.rbx = new,
            4 => self.regs.rsp = new,
            5 => self.regs.rbp = new,
            6 => self.regs.rsi = new,
            7 => self.regs.rdi = new,
            else => unreachable,
        }
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

    fn execute(self: *ElfState, d: DecodedInsn) void {
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

            // ── add reg, mem ──
            .add_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, .bits8, a +% b);
            },
            .add_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits16, a +% b);
            },
            .add_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                self.setReg(d.dst_reg, .bits32, a +% b);
            },
            .add_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                self.setReg(d.dst_reg, .bits64, a +% b);
            },

            // ── sub reg, mem ──
            .sub_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, .bits8, a -% b);
            },
            .sub_reg16_mem16 => {
                const a = self.regVal(d.dst_reg, .bits16);
                const b = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits16, a -% b);
            },
            .sub_reg32_mem32 => {
                const a = self.regVal(d.dst_reg, .bits32);
                const b = self.readMemVal(d.addr, .bits32);
                self.setReg(d.dst_reg, .bits32, a -% b);
            },
            .sub_reg64_mem64 => {
                const a = self.regVal(d.dst_reg, .bits64);
                const b = self.readMemVal(d.addr, .bits64);
                self.setReg(d.dst_reg, .bits64, a -% b);
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
            .movzx_reg32_mem16 => {
                const val = self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, .bits32, val);
            },
            .movsx_reg32_mem16 => {
                const val = @as(i32, @as(i16, @bitCast(@as(u16, @truncate(self.readMemVal(d.addr, .bits16))))));
                self.setReg(d.dst_reg, .bits32, @as(u32, @bitCast(val)));
            },
            .movsxd_reg64_reg32 => {
                const val = @as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regVal(d.src_reg, .bits32))))));
                self.setReg(d.dst_reg, .bits64, @as(u64, @bitCast(val)));
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
            self.regs.rax = @bitCast(@as(i64, -14));
            return;
        };
        if (count > std.math.maxInt(usize)) {
            self.regs.rax = @bitCast(@as(i64, -14));
            return;
        }
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) {
            self.regs.rax = @bitCast(@as(i64, -14));
            return;
        }

        const data = self.mem[off_usize .. off_usize + count_usize];
        if (fd == 1) {
            writeHostAll(std.posix.STDOUT_FILENO, data) catch {
                self.regs.rax = @bitCast(@as(i64, -5));
                return;
            };
            self.regs.rax = count;
        } else if (fd == 2) {
            writeHostAll(std.posix.STDERR_FILENO, data) catch {
                self.regs.rax = @bitCast(@as(i64, -5));
                return;
            };
            self.regs.rax = count;
        } else {
            self.regs.rax = @bitCast(@as(i64, -9));
        }
    }
};

fn writeHostAll(fd: std.c.fd_t, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const n = std.c.write(fd, data[written..].ptr, data.len - written);
        if (n <= 0) return error.WriteFailed;
        written += @intCast(n);
    }
}

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

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};

    var pos: usize = 0;
    var rex: u8 = 0;
    var has_66: bool = false;

    // Parse prefixes
    while (pos < bytes.len and pos < 15) {
        const b = bytes[pos];
        if (b == 0x66) {
            has_66 = true;
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
    const rex_b = rexB(rex);

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
            const d = (opcode >> 1) & 1; // d=1 means reg is dst, d=0 means reg is src

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod == 0 and rm == 4) {
                // SIB follows
                if (pos >= bytes.len) return .{};
                const sib_byte = bytes[pos];
                pos += 1;
                _ = (sib_byte >> 3) & 7;
                const sib_base = sib_byte & 7;
                if (sib_base == 5 and mod == 0 and d == 1) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(if (rex_b) reg | 8 else reg)));
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .add_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .add_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .add_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .add_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                // Register form - skip for now
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(if (rex_b) reg | 8 else reg)));
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .sub_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .sub_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .sub_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .sub_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod == 3) {
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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
                    .dst_reg = @enumFromInt(@as(u3, @truncate(reg))),
                    .src_reg = @enumFromInt(@as(u3, @truncate(if (rex_b) rm | 8 else rm))),
                    .len = @intCast(pos),
                };
            }
            return .{};
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

            if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                _ = (sib >> 3) & 7;
                if (base == 5 and mod_v == 0) {
                    const src_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .mov_mem8_reg8, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mov_mem16_reg16, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mov_mem32_reg32, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mov_mem64_reg64, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod_v == 3) {
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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
            const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));

            if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                if (base == 5) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                    };
                }
            }

            if (mod_v == 3) {
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x98 => {
            // CBW/CWDE/CDQE
            if (rex_w) {
                // CDQE (RAX = sign-extend EAX)
                return DecodedInsn{ .op = .cqo, .len = @intCast(pos) };
            } else if (has_66) {
                // CBW (AX = sign-extend AL)
                return DecodedInsn{ .op = .cbw, .len = @intCast(pos) };
            } else {
                // CWDE (EAX = sign-extend AX)
                return DecodedInsn{ .op = .cwd, .len = @intCast(pos) };
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

        0xB8, 0xB9, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF => {
            // MOV r, imm32 (with REX.W: imm32 sign-extended)
            const reg_bits = opcode - 0xB8;
            const reg: RegId = @enumFromInt(@as(u3, @truncate(reg_bits)));
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

        0xBA => {
            // MOV DX/EDX/RDX, imm
            if (pos + 4 > bytes.len) return .{};
            if (has_66) {
                const imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
                pos += 2;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits16, .dst_reg = .dl_dx_edx_rdx, .imm = imm, .len = @intCast(pos) };
            } else if (rex_w) {
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits64, .dst_reg = .dl_dx_edx_rdx, .imm = imm, .len = @intCast(pos) };
            } else {
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{ .op = .mov_reg_imm, .size = .bits32, .dst_reg = .dl_dx_edx_rdx, .imm = imm, .len = @intCast(pos) };
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

            if (reg_field != 0) return .{}; // only /0 is MOV

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (mod_v == 3) {
                // MOV reg, imm32
                if (pos + 4 > bytes.len) return .{};
                const imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                pos += 4;
                return DecodedInsn{
                    .op = .mov_reg_imm,
                    .size = size,
                    .dst_reg = @enumFromInt(@as(u3, @truncate(rm))),
                    .imm = if (size == .bits64) @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(imm))))) else imm,
                    .len = @intCast(pos),
                };
            }

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xE8 => {
            // CALL rel32
            if (pos + 4 > bytes.len) return .{};
            const rel = std.mem.readInt(i32, bytes[pos..][0..4], .little);
            pos += 4;
            _ = rel;
            // Not supported yet
            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0xEB => {
            // JMP short rel8
            if (pos >= bytes.len) return .{};
            pos += 1;
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

            if (mod_v == 0) {
                if (rm == 4) {
                    // SIB follows: expected 04 25 [addr] pattern
                    if (pos >= bytes.len) return .{};
                    const sib_byte = bytes[pos];
                    pos += 1;
                    const base = sib_byte & 7;
                    const index = (sib_byte >> 3) & 7;
                    if (base == 5 and index == 4) {
                        // [abs32] addressing
                        if (pos + 4 > bytes.len) return .{};
                        const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                        pos += 4;

                        return switch (reg_field) {
                            4 => switch (size) {
                                .bits8 => DecodedInsn{ .op = .mul_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits16 => DecodedInsn{ .op = .mul_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits32 => DecodedInsn{ .op = .mul_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits64 => DecodedInsn{ .op = .mul_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                            },
                            5 => switch (size) {
                                .bits8 => DecodedInsn{ .op = .imul_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits16 => DecodedInsn{ .op = .imul_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits32 => DecodedInsn{ .op = .imul_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits64 => DecodedInsn{ .op = .imul_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                            },
                            6 => switch (size) {
                                .bits8 => DecodedInsn{ .op = .div_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits16 => DecodedInsn{ .op = .div_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits32 => DecodedInsn{ .op = .div_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits64 => DecodedInsn{ .op = .div_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                            },
                            7 => switch (size) {
                                .bits8 => DecodedInsn{ .op = .idiv_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits16 => DecodedInsn{ .op = .idiv_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits32 => DecodedInsn{ .op = .idiv_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                                .bits64 => DecodedInsn{ .op = .idiv_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                            },
                            else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                        };
                    }
                }
            } else if (mod_v == 3) {
                // Register form: Group 3 with register operand
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
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

            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
        },

        0x0F => {
            // Two-byte opcodes
            if (pos >= bytes.len) return .{};
            const op2 = bytes[pos];
            pos += 1;

            switch (op2) {
                0x05 => {
                    // SYSCALL
                    return DecodedInsn{ .op = .syscall, .len = @intCast(pos) };
                },
                0xB7 => {
                    // MOVZX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;

                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));

                    if (mod_v == 0 and rm == 4) {
                        if (pos >= bytes.len) return .{};
                        const sib = bytes[pos];
                        pos += 1;
                        const base = sib & 7;
                        if (base == 5) {
                            if (pos + 4 > bytes.len) return .{};
                            const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                            pos += 4;
                            return DecodedInsn{ .op = .movzx_reg32_mem16, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) };
                        }
                    }

                    return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                },
                0xBF => {
                    // MOVSX r32, r/m16
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;

                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));

                    if (mod_v == 0 and rm == 4) {
                        if (pos >= bytes.len) return .{};
                        const sib = bytes[pos];
                        pos += 1;
                        const base = sib & 7;
                        if (base == 5) {
                            if (pos + 4 > bytes.len) return .{};
                            const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                            pos += 4;
                            return DecodedInsn{ .op = .movsx_reg32_mem16, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) };
                        }
                    }

                    return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                },
                else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
            }
        },

        else => return DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
    }
}

// ─── High-level API ───

pub fn loadAndRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    state.regs.rsp = MEM_BASE + MEM_SIZE - 8;

    state.run();

    return state.exit_code;
}

/// CLI entry point: `elf_processor <path-to-elf>`
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        log.err("usage: elf_processor <elf-path>", .{});
        return;
    }
    const elf_path = args[1];

    const elf_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, elf_path, init.arena.allocator(), .unlimited);

    const exit_code = loadAndRunElf(init.arena.allocator(), elf_bytes) catch |err| {
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

// Full-binary integration test is available via CLI: `zig run ELF_processor/process.zig -- <elf-path>`
