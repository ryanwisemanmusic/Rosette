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

const SHT_SYMTAB: u32 = 2;
const SHN_UNDEF: u16 = 0;

const SYS_exit: u64 = 60;
const SYS_write: u64 = 1;

// ─── RFLAGS bit positions ───
const RFL_CF: u32 = 1 << 0;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF: u32 = 1 << 6;
const RFL_SF: u32 = 1 << 7;
const RFL_OF: u32 = 1 << 11;

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

const Elf64_Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u64,
    sh_addr: u64,
    sh_offset: u64,
    sh_size: u64,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u64,
    sh_entsize: u64,
};

const Elf64_Sym = extern struct {
    st_name: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
    st_value: u64,
    st_size: u64,
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

pub const Cond = enum(u4) {
    o = 0,
    no = 1,
    b = 2,
    ae = 3,
    e = 4,
    ne = 5,
    be = 6,
    a = 7,
    s = 8,
    ns = 9,
    p = 10,
    np = 11,
    l = 12,
    ge = 13,
    le = 14,
    g = 15,
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
    mov_mem16_imm16,
    mov_mem32_imm32,
    mov_mem64_imm32,
    mov_reg64_reg64,
    // add (reg, r/m) d=1
    add_reg8_mem8,
    add_reg16_mem16,
    add_reg32_mem32,
    add_reg64_mem64,
    // add (r/m, reg) d=0
    add_mem8_reg8,
    add_mem16_reg16,
    add_mem32_reg32,
    add_mem64_reg64,
    // add reg, reg
    add_reg8_reg8,
    add_reg16_reg16,
    add_reg32_reg32,
    add_reg64_reg64,
    // sub (reg, r/m) d=1
    sub_reg8_mem8,
    sub_reg16_mem16,
    sub_reg32_mem32,
    sub_reg64_mem64,
    // sub (reg, reg) mod=3
    sub_reg8_reg8,
    sub_reg16_reg16,
    sub_reg32_reg32,
    sub_reg64_reg64,
    // cmp r/m, r
    cmp_mem8_reg8,
    cmp_mem16_reg16,
    cmp_mem32_reg32,
    cmp_mem64_reg64,
    cmp_reg8_reg8,
    cmp_reg16_reg16,
    cmp_reg32_reg32,
    cmp_reg64_reg64,
    // cmp reg, r/m (3A/3B, d=1)
    cmp_reg8_mem8,
    cmp_reg16_mem16,
    cmp_reg32_mem32,
    cmp_reg64_mem64,
    // cmp r/m, imm8 (83 /7)
    cmp_mem8_imm8,
    cmp_mem16_imm8,
    cmp_mem32_imm8,
    cmp_mem64_imm8,
    cmp_reg8_imm8,
    cmp_reg16_imm8,
    cmp_reg32_imm8,
    cmp_reg64_imm8,
    // inc/dec
    inc_mem8,
    inc_mem16,
    inc_mem32,
    inc_mem64,
    inc_reg8,
    inc_reg16,
    inc_reg32,
    inc_reg64,
    dec_mem8,
    dec_mem16,
    dec_mem32,
    dec_mem64,
    dec_reg8,
    dec_reg16,
    dec_reg32,
    dec_reg64,
    // mul/imul/div/idiv (memory) — unchanged
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
    // mul/imul/div/idiv (register) — unchanged
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
    // imul r, r/m (0F AF)
    imul_reg64_mem64,
    imul_reg64_reg64,
    imul_reg32_mem32,
    imul_reg32_reg32,
    // imul r, r/m, imm8 (6B)
    imul_reg64_mem64_imm8,
    imul_reg64_reg64_imm8,
    imul_reg32_mem32_imm8,
    imul_reg32_reg32_imm8,
    // sign extend
    cbw,
    cwd,
    cdq,
    cqo,
    // zero/sign extend loads
    movzx_reg32_mem8,
    movzx_reg32_mem16,
    movsx_reg32_mem8,
    movsx_reg32_mem16,
    movsxd_reg64_reg32,
    // conditional / unconditional jumps
    jmp_rel8,
    jcc_rel8,
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
    // SIB indexed addressing
    sib_has_index: bool = false,
    sib_index_reg: RegId = .al_ax_eax_rax,
    sib_scale: u2 = 0,
    sib_has_base: bool = false,
    sib_base_reg: RegId = .al_ax_eax_rax,
    // address-size override
    has_0x67: bool = false,
    // register form (true when mod=3 register-to-register)
    is_reg_form: bool = false,
    // conditional jump condition
    cond: Cond = .e,
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

    fn setFlagsSub(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        const mask: u64 = switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFFFFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
        const r = result & mask;
        const a_s = @as(i64, @bitCast(a & mask));
        const b_s = @as(i64, @bitCast(b & mask));
        const r_s = @as(i64, @bitCast(r));
        // CF: borrow from MSB (unsigned)
        if ((a & mask) < (b & mask)) {
            self.regs.rflags |= RFL_CF;
        } else {
            self.regs.rflags &= ~RFL_CF;
        }
        // OF: signed overflow
        if ((a_s < 0 and b_s > 0 and r_s >= 0) or (a_s >= 0 and b_s < 0 and r_s < 0)) {
            self.regs.rflags |= RFL_OF;
        } else {
            self.regs.rflags &= ~RFL_OF;
        }
        // SF: sign bit
        if (r_s < 0) {
            self.regs.rflags |= RFL_SF;
        } else {
            self.regs.rflags &= ~RFL_SF;
        }
        // ZF: zero
        if (r == 0) {
            self.regs.rflags |= RFL_ZF;
        } else {
            self.regs.rflags &= ~RFL_ZF;
        }
    }

    fn setFlagsAdd(self: *ElfState, a: u64, b: u64, result: u64, size: Size) void {
        const mask: u64 = switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFFFFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
        const r = result & mask;
        const a_s = @as(i64, @bitCast(a & mask));
        const b_s = @as(i64, @bitCast(b & mask));
        const r_s = @as(i64, @bitCast(r));
        // CF: carry out of MSB
        if (result > mask) {
            self.regs.rflags |= RFL_CF;
        } else {
            self.regs.rflags &= ~RFL_CF;
        }
        // OF: signed overflow
        if ((a_s >= 0 and b_s >= 0 and r_s < 0) or (a_s < 0 and b_s < 0 and r_s >= 0)) {
            self.regs.rflags |= RFL_OF;
        } else {
            self.regs.rflags &= ~RFL_OF;
        }
        // SF
        if (r_s < 0) {
            self.regs.rflags |= RFL_SF;
        } else {
            self.regs.rflags &= ~RFL_SF;
        }
        // ZF
        if (r == 0) {
            self.regs.rflags |= RFL_ZF;
        } else {
            self.regs.rflags &= ~RFL_ZF;
        }
    }

    fn setFlagsIncDec(self: *ElfState, input: u64, result: u64, size: Size, is_inc: bool) void {
        const mask: u64 = switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFFFFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
        const r = result & mask;
        const input_s = @as(i64, @bitCast(input & mask));
        const r_s = @as(i64, @bitCast(r));
        // CF not affected
        // OF: overflow for signed (sign change at boundary)
        const overflow = if (is_inc)
            input_s == std.math.maxInt(i64) & @as(i64, @bitCast(mask))
        else
            input_s == std.math.minInt(i64) & @as(i64, @bitCast(mask));
        if (overflow) {
            self.regs.rflags |= RFL_OF;
        } else {
            self.regs.rflags &= ~RFL_OF;
        }
        // SF
        if (r_s < 0) {
            self.regs.rflags |= RFL_SF;
        } else {
            self.regs.rflags &= ~RFL_SF;
        }
        // ZF
        if (r == 0) {
            self.regs.rflags |= RFL_ZF;
        } else {
            self.regs.rflags &= ~RFL_ZF;
        }
    }

    fn evalCond(rflags: u32, cond: Cond) bool {
        const sf = (rflags & RFL_SF) != 0;
        const zf = (rflags & RFL_ZF) != 0;
        const of = (rflags & RFL_OF) != 0;
        const cf = (rflags & RFL_CF) != 0;
        return switch (cond) {
            .o => of,
            .no => !of,
            .b => cf,
            .ae => !cf,
            .e => zf,
            .ne => !zf,
            .be => cf or zf,
            .a => !cf and !zf,
            .s => sf,
            .ns => !sf,
            .p => false, // parity not tracked
            .np => true,
            .l => sf != of,
            .ge => sf == of,
            .le => zf or (sf != of),
            .g => !zf and (sf == of),
        };
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

fn parseSib(bytes: []const u8, pos: *usize, mod: u3) ?struct { addr: u64, sib_has_index: bool, sib_index_reg: RegId, sib_scale: u2, sib_has_base: bool, sib_base_reg: RegId } {
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
        .sib_index_reg = @enumFromInt(@as(u3, @truncate(index))),
        .sib_scale = scale,
        .sib_has_base = !(mod == 0 and base == 5),
        .sib_base_reg = @enumFromInt(@as(u3, @truncate(base))),
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
            const d = (opcode >> 1) & 1;

            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else if (w == 1) .bits32 else .bits8;

            if (mod == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib_byte = bytes[pos];
                pos += 1;
                const sib_index = (sib_byte >> 3) & 7;
                const sib_base = sib_byte & 7;
                if (sib_base == 5 and sib_index == 4 and mod == 0) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    if (d == 1) {
                        const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .add_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .add_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .add_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .add_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                        };
                    } else {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                        return switch (size) {
                            .bits8 => DecodedInsn{ .op = .add_mem8_reg8, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .add_mem16_reg16, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .add_mem32_reg32, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .add_mem64_reg64, .size = size, .src_reg = src_reg, .addr = addr, .len = @intCast(pos) },
                        };
                    }
                }
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            }

            if (mod == 3) {
                const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) reg else rm)));
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) rm else reg)));
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
                const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) reg else rm)));
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) rm else reg)));
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
                const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) reg else rm)));
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(if (d == 1) rm else reg)));
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_reg8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_reg16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (rm == 4) {
                const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                if (d == 0) {
                    // cmp r/m, r: source is reg, dst is [addr]
                    const src_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_reg8, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_reg16, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_reg32, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_reg64, .size = size, .src_reg = src_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    };
                } else {
                    // cmp reg, r/m: dst is reg, source is [addr]
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
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
                    .dst_reg = @enumFromInt(@as(u3, @truncate(reg))),
                    .src_reg = @enumFromInt(@as(u3, @truncate(if (rex_b) rm | 8 else rm))),
                    .len = @intCast(pos),
                };
            }
            return .{};
        },

        0x6B => {
            // IMUL r, r/m, imm8
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
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
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                return switch (size) {
                    .bits32 => DecodedInsn{ .op = .imul_reg32_reg32_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .imul_reg64_reg64_imm8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .imm = imm, .len = @intCast(pos) },
                    else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                };
            }
            return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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

        0x83 => {
            // Group 1: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP with imm8 sign-extended
            // We only handle /7 (CMP) for now
            if (pos >= bytes.len) return .{};
            const modrm = bytes[pos];
            pos += 1;
            const mod_v = modrm >> 6;
            const reg_field = (modrm >> 3) & 7;
            const rm = modrm & 7;
            const size: Size = if (has_66) .bits16 else if (rex_w) .bits64 else .bits32;

            if (reg_field != 7) return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };

            if (pos >= bytes.len) return .{};
            const imm = bytes[pos];
            pos += 1;

            if (mod_v == 3) {
                const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .cmp_reg8_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .cmp_reg16_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .cmp_reg32_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .cmp_reg64_imm8, .size = size, .dst_reg = dst_reg, .imm = imm, .len = @intCast(pos) },
                };
            } else if (mod_v == 0 and rm == 4) {
                if (pos >= bytes.len) return .{};
                const sib = bytes[pos];
                pos += 1;
                const base = sib & 7;
                const sib_idx = (sib >> 3) & 7;
                if (base == 5 and sib_idx == 4) {
                    if (pos + 4 > bytes.len) return .{};
                    const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                    pos += 4;
                    return switch (size) {
                        .bits8 => DecodedInsn{ .op = .cmp_mem8_imm8, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits16 => DecodedInsn{ .op = .cmp_mem16_imm8, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .cmp_mem32_imm8, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .cmp_mem64_imm8, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                    };
                }
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
            const src_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));

            if (mod_v == 3) {
                if (opcode == 0x89 and size == .bits64) {
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                    return DecodedInsn{ .op = .mov_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) };
                }
                return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
            }

            if (rm == 4) {
                const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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
            const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));

            if (mod_v == 3) {
                const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                };
            }

            if (rm == 4) {
                const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                return switch (size) {
                    .bits8 => DecodedInsn{ .op = .mov_reg8_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits16 => DecodedInsn{ .op = .mov_reg16_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits32 => DecodedInsn{ .op = .mov_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                    .bits64 => DecodedInsn{ .op = .mov_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) },
                };
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
                    .dst_reg = @enumFromInt(@as(u3, @truncate(rm))),
                    .imm = if (size == .bits64) @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(imm))))) else imm,
                    .len = @intCast(pos),
                };
            }

            // Memory form
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
                    const imm_len: usize = if (size == .bits16) 2 else 4;
                    if (pos + imm_len > bytes.len) return .{};
                    const imm = if (size == .bits16)
                        @as(u64, std.mem.readInt(u16, bytes[pos..][0..2], .little))
                    else
                        @as(u64, std.mem.readInt(u32, bytes[pos..][0..4], .little));
                    pos += imm_len;
                    return switch (size) {
                        .bits16 => DecodedInsn{ .op = .mov_mem16_imm16, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits32 => DecodedInsn{ .op = .mov_mem32_imm32, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        .bits64 => DecodedInsn{ .op = .mov_mem64_imm32, .size = size, .addr = addr, .imm = imm, .len = @intCast(pos) },
                        else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                    };
                }
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
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
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
                } else if (mod_v == 0 and rm == 4) {
                    if (pos >= bytes.len) return .{};
                    const sib = bytes[pos];
                    pos += 1;
                    const base = sib & 7;
                    const sib_idx = (sib >> 3) & 7;
                    if (base == 5 and sib_idx == 4) {
                        if (pos + 4 > bytes.len) return .{};
                        const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                        pos += 4;
                        return if (is_inc) switch (size) {
                            .bits8 => DecodedInsn{ .op = .inc_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .inc_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .inc_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .inc_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                        } else switch (size) {
                            .bits8 => DecodedInsn{ .op = .dec_mem8, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits16 => DecodedInsn{ .op = .dec_mem16, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits32 => DecodedInsn{ .op = .dec_mem32, .size = size, .addr = addr, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .dec_mem64, .size = size, .addr = addr, .len = @intCast(pos) },
                        };
                    }
                }
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
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                    const size: Size = if (rex_w) .bits64 else .bits32;

                    if (mod_v == 0 and rm == 4) {
                        if (pos >= bytes.len) return .{};
                        const sib = bytes[pos];
                        pos += 1;
                        const base = sib & 7;
                        const sib_idx = (sib >> 3) & 7;
                        if (base == 5 and sib_idx == 4) {
                            if (pos + 4 > bytes.len) return .{};
                            const addr = std.mem.readInt(u32, bytes[pos..][0..4], .little);
                            pos += 4;
                            return switch (size) {
                                .bits32 => DecodedInsn{ .op = .imul_reg32_mem32, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                                .bits64 => DecodedInsn{ .op = .imul_reg64_mem64, .size = size, .dst_reg = dst_reg, .addr = addr, .len = @intCast(pos) },
                                else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                            };
                        }
                    } else if (mod_v == 3) {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                        return switch (size) {
                            .bits32 => DecodedInsn{ .op = .imul_reg32_reg32, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            .bits64 => DecodedInsn{ .op = .imul_reg64_reg64, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .len = @intCast(pos) },
                            else => DecodedInsn{ .op = .invalid, .len = @intCast(pos) },
                        };
                    }
                    return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                },
                0xB6 => {
                    // MOVZX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                        return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    if (rm == 4) {
                        const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movzx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) };
                    }
                    return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
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
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                        return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    if (rm == 4) {
                        const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movzx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) };
                    }
                    return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                },
                0xBE => {
                    // MOVSX r32, r/m8
                    if (pos >= bytes.len) return .{};
                    const modrm = bytes[pos];
                    pos += 1;
                    const mod_v = modrm >> 6;
                    const reg = (modrm >> 3) & 7;
                    const rm = modrm & 7;
                    const dst_reg: RegId = @enumFromInt(@as(u3, @truncate(reg)));
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                        return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    if (rm == 4) {
                        const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movsx_reg32_mem8, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) };
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
                    const size: Size = if (rex_w) .bits64 else .bits32;
                    if (mod_v == 3) {
                        const src_reg: RegId = @enumFromInt(@as(u3, @truncate(rm)));
                        return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .src_reg = src_reg, .is_reg_form = true, .len = @intCast(pos) };
                    }
                    if (rm == 4) {
                        const sib_info = parseSib(bytes, &pos, @as(u3, @truncate(mod_v))) orelse return DecodedInsn{ .op = .invalid, .len = @intCast(pos) };
                        return DecodedInsn{ .op = .movsx_reg32_mem16, .size = size, .dst_reg = dst_reg, .addr = sib_info.addr, .sib_has_index = sib_info.sib_has_index, .sib_index_reg = sib_info.sib_index_reg, .sib_scale = sib_info.sib_scale, .sib_has_base = sib_info.sib_has_base, .sib_base_reg = sib_info.sib_base_reg, .len = @intCast(pos) };
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
    return loadRunElf(allocator, elf_bytes, .{});
}

const ElfRunOptions = struct {
    dump_results: bool = false,
    dump_all_results: bool = false,
    source_text: ?[]const u8 = null,
};

fn loadRunElf(allocator: std.mem.Allocator, elf_bytes: []const u8, options: ElfRunOptions) !u64 {
    var state = ElfState.init(allocator);
    defer state.deinit();

    try state.loadElf(elf_bytes);

    var result_symbols: std.ArrayList(DumpSymbol) = .empty;
    defer result_symbols.deinit(allocator);
    if (options.dump_results) {
        result_symbols = collectResultSymbols(allocator, &state, elf_bytes) catch |err| blk: {
            log.warn("result symbols unavailable: {s}", .{@errorName(err)});
            break :blk .empty;
        };
    }

    state.regs.rsp = MEM_BASE + MEM_SIZE - 8;

    state.run();

    if (options.dump_results) {
        dumpResultSymbols(allocator, &state, result_symbols.items, options) catch |err| {
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

const DumpSymbol = struct {
    name: []const u8,
    addr: u64,
    size: usize,
    initial: [32]u8 = [_]u8{0} ** 32,
};

const ResultExpression = struct {
    name: []const u8,
    text: []const u8,
};

fn collectResultSymbols(allocator: std.mem.Allocator, state: *const ElfState, elf_bytes: []const u8) !std.ArrayList(DumpSymbol) {
    if (elf_bytes.len < @sizeOf(Elf64_Ehdr)) return error.InvalidElf;
    const ehdr = @as(*const Elf64_Ehdr, @ptrCast(@alignCast(elf_bytes[0..@sizeOf(Elf64_Ehdr)])));
    if (ehdr.e_shoff == 0 or ehdr.e_shnum == 0) return .empty;
    if (ehdr.e_shentsize < @sizeOf(Elf64_Shdr)) return error.InvalidSectionHeaderSize;
    const section_table_size = @as(u64, ehdr.e_shentsize) * @as(u64, ehdr.e_shnum);
    if (ehdr.e_shoff > elf_bytes.len or section_table_size > elf_bytes.len - ehdr.e_shoff) return error.TruncatedSectionHeaders;

    var symbols: std.ArrayList(DumpSymbol) = .empty;
    errdefer symbols.deinit(allocator);

    var section_index: u16 = 0;
    while (section_index < ehdr.e_shnum) : (section_index += 1) {
        const shdr = readSectionHeader(elf_bytes, ehdr, section_index) orelse return error.TruncatedSectionHeaders;
        if (shdr.sh_type != SHT_SYMTAB) continue;
        if (shdr.sh_entsize < @sizeOf(Elf64_Sym) or shdr.sh_entsize == 0) continue;
        if (shdr.sh_link >= ehdr.e_shnum) continue;

        const strtab_shdr = readSectionHeader(elf_bytes, ehdr, @intCast(shdr.sh_link)) orelse continue;
        const strtab = sectionBytes(elf_bytes, strtab_shdr) orelse continue;
        const symtab = sectionBytes(elf_bytes, shdr) orelse continue;
        const sym_count = shdr.sh_size / shdr.sh_entsize;

        var sym_index: u64 = 0;
        while (sym_index < sym_count) : (sym_index += 1) {
            const sym_offset = sym_index * shdr.sh_entsize;
            if (sym_offset + @sizeOf(Elf64_Sym) > symtab.len) break;
            const sym = @as(*const Elf64_Sym, @ptrCast(@alignCast(symtab[sym_offset..][0..@sizeOf(Elf64_Sym)])));
            if (sym.st_shndx == SHN_UNDEF or sym.st_value == 0) continue;

            const name = elfString(strtab, sym.st_name) orelse continue;
            if (!isResultSymbolName(name)) continue;

            const size = inferResultSymbolSize(name, sym.st_size);
            if (size == 0) continue;
            const mem_offset = state.addrToOffset(sym.st_value) orelse continue;
            if (mem_offset + size > state.mem.len) continue;

            var dump_symbol = DumpSymbol{
                .name = name,
                .addr = sym.st_value,
                .size = size,
            };
            copySymbolBytes(state, sym.st_value, size, &dump_symbol.initial);
            try appendDumpSymbolSorted(allocator, &symbols, dump_symbol);
        }
    }

    return symbols;
}

fn dumpResultSymbols(allocator: std.mem.Allocator, state: *const ElfState, symbols: []const DumpSymbol, options: ElfRunOptions) !void {
    if (symbols.len == 0) {
        dumpPrint("Rosette ELF results: no answer/remainder symbols found\n", .{});
        return;
    }

    var expressions: std.ArrayList(ResultExpression) = .empty;
    defer expressions.deinit(allocator);
    if (options.source_text) |source_text| {
        expressions = try collectResultExpressions(allocator, source_text);
    }

    var printed: usize = 0;
    for (symbols) |symbol| {
        if (!options.dump_all_results and !symbolChanged(state, symbol)) continue;
        printed += 1;
    }

    if (printed == 0) {
        dumpPrint("Rosette ELF results: no answer/remainder values changed\n", .{});
        dumpPrint("  Set ROSETTE_ELF_DUMP_ALL=1 to include unchanged placeholders.\n", .{});
        return;
    }

    if (options.dump_all_results) {
        dumpPrint("Rosette ELF result summary ({d} symbols):\n", .{printed});
    } else {
        dumpPrint("Rosette ELF result summary ({d} changed symbols):\n", .{printed});
    }

    for (symbols) |symbol| {
        if (!options.dump_all_results and !symbolChanged(state, symbol)) continue;
        printDumpSymbol(state, symbol, findResultExpression(expressions.items, symbol.name));
    }
}

fn readSectionHeader(elf_bytes: []const u8, ehdr: *const Elf64_Ehdr, index: u16) ?*const Elf64_Shdr {
    const offset = ehdr.e_shoff + @as(u64, index) * ehdr.e_shentsize;
    if (offset + @sizeOf(Elf64_Shdr) > elf_bytes.len) return null;
    return @as(*const Elf64_Shdr, @ptrCast(@alignCast(elf_bytes[offset..][0..@sizeOf(Elf64_Shdr)])));
}

fn sectionBytes(elf_bytes: []const u8, shdr: *const Elf64_Shdr) ?[]const u8 {
    if (shdr.sh_offset > elf_bytes.len) return null;
    if (shdr.sh_size > elf_bytes.len - shdr.sh_offset) return null;
    return elf_bytes[shdr.sh_offset..][0..@intCast(shdr.sh_size)];
}

fn elfString(strtab: []const u8, offset: u32) ?[]const u8 {
    if (offset >= strtab.len) return null;
    const rest = strtab[offset..];
    const len = std.mem.indexOfScalar(u8, rest, 0) orelse return null;
    return rest[0..len];
}

fn isResultSymbolName(name: []const u8) bool {
    return containsAsciiIgnoreCase(name, "ans") or containsAsciiIgnoreCase(name, "rem");
}

fn containsAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn inferResultSymbolSize(name: []const u8, reported_size: u64) usize {
    if (reported_size > 0 and reported_size <= 32) return @intCast(reported_size);
    if (name.len >= 2 and std.ascii.toLower(name[0]) == 'd' and std.ascii.toLower(name[1]) == 'q') return 16;
    if (name.len == 0) return 0;
    return switch (std.ascii.toLower(name[0])) {
        'b' => 1,
        'w' => 2,
        'd' => 4,
        'q' => 8,
        else => 0,
    };
}

fn copySymbolBytes(state: *const ElfState, addr: u64, size: usize, out: *[32]u8) void {
    const start = state.addrToOffset(addr) orelse return;
    if (start + size > state.mem.len or size > out.len) return;
    @memcpy(out[0..size], state.mem[start..][0..size]);
}

fn symbolChanged(state: *const ElfState, symbol: DumpSymbol) bool {
    const start = state.addrToOffset(symbol.addr) orelse return false;
    if (start + symbol.size > state.mem.len or symbol.size > symbol.initial.len) return false;
    return !std.mem.eql(u8, state.mem[start..][0..symbol.size], symbol.initial[0..symbol.size]);
}

fn appendDumpSymbolSorted(allocator: std.mem.Allocator, symbols: *std.ArrayList(DumpSymbol), symbol: DumpSymbol) !void {
    var insert_at: usize = 0;
    while (insert_at < symbols.items.len and symbols.items[insert_at].addr <= symbol.addr) : (insert_at += 1) {}

    try symbols.append(allocator, symbol);
    var i = symbols.items.len - 1;
    while (i > insert_at) : (i -= 1) {
        symbols.items[i] = symbols.items[i - 1];
    }
    symbols.items[insert_at] = symbol;
}

fn printDumpSymbol(state: *const ElfState, symbol: DumpSymbol, expression: ?[]const u8) void {
    if (expression) |text| {
        dumpPrint("  {s} -> ", .{text});
    } else {
        dumpPrint("  {s} -> ", .{symbol.name});
    }
    switch (symbol.size) {
        1 => {
            const value = state.read8(symbol.addr);
            const signed: i8 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        2 => {
            const value = state.read16(symbol.addr);
            const signed: i16 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        4 => {
            const value = state.read32(symbol.addr);
            const signed: i32 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        8 => {
            const value = state.read64(symbol.addr);
            const signed: i64 = @bitCast(value);
            dumpPrint("signed {d}, unsigned {d}, hex 0x{x}", .{ signed, value, value });
        },
        16 => {
            const lo = state.read64(symbol.addr);
            const hi = state.read64(symbol.addr + 8);
            const combined = (@as(u128, hi) << 64) | lo;
            dumpPrint("unsigned {d}, hex 0x{x}, high {d}, low {d}", .{ combined, combined, hi, lo });
        },
        else => {
            dumpPrint("bytes=", .{});
            printHexBytes(state, symbol.addr, symbol.size);
        },
    }
    dumpPrint("\n", .{});
}

fn collectResultExpressions(allocator: std.mem.Allocator, source_text: []const u8) !std.ArrayList(ResultExpression) {
    var expressions: std.ArrayList(ResultExpression) = .empty;
    errdefer expressions.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source_text, '\n');
    while (lines.next()) |line| {
        const comment_start = std.mem.indexOfScalar(u8, line, ';') orelse continue;
        const comment = std.mem.trim(u8, line[comment_start + 1 ..], " \t\r\n");
        const eq = std.mem.indexOfScalar(u8, comment, '=') orelse continue;
        const lhs = std.mem.trim(u8, comment[0..eq], " \t\r\n");
        if (!isResultSymbolName(lhs)) continue;
        const rhs = std.mem.trim(u8, comment[eq + 1 ..], " \t\r\n");
        if (rhs.len == 0) continue;
        if (findResultExpression(expressions.items, lhs) != null) continue;
        try expressions.append(allocator, .{
            .name = lhs,
            .text = comment,
        });
    }

    return expressions;
}

fn findResultExpression(expressions: []const ResultExpression, name: []const u8) ?[]const u8 {
    for (expressions) |expression| {
        if (std.mem.eql(u8, expression.name, name)) return expression.text;
    }
    return null;
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

fn printHexBytes(state: *const ElfState, addr: u64, size: usize) void {
    const start = state.addrToOffset(addr) orelse return;
    if (start + size > state.mem.len) return;

    dumpPrint("0x", .{});
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const byte = state.mem[start + i];
        printHexByte(byte);
    }
}

fn printHexByte(byte: u8) void {
    const alphabet = "0123456789abcdef";
    dumpPrint("{c}{c}", .{ alphabet[@as(usize, byte >> 4)], alphabet[@as(usize, byte & 0x0f)] });
}

fn dumpPrint(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, fmt, args) catch return;
    writeHostAll(std.posix.STDOUT_FILENO, text) catch {};
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

// Full-binary integration test (manual): zig run ELF_processor/process.zig -- test/Internal_Assembly/x86-64-Ast02-main/ast02
// Ast02 verified: exit_code=0, sum=6213, avg=82, estMedian=-2589, min=-32768, max=25000,
//   countEven=42, sumEven=-9012, avgEven=-214, countFive=28, sumFive=30567, avgFive=1091
