const flags = @import("flags.zig");

pub const OperandSize = flags.OperandSize;

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

pub const Regs = struct {
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

    pub fn get(self: *const Regs, comptime reg: []const u8) u64 {
        _ = self;
        _ = reg;
        return 0;
    }
};

pub fn regVal(regs: *const Regs, id: RegId, size: OperandSize) u64 {
    const r = @as(u64, @intFromEnum(id));
    const val: u64 = switch (r) {
        0 => regs.rax,
        1 => regs.rcx,
        2 => regs.rdx,
        3 => regs.rbx,
        4 => regs.rsp,
        5 => regs.rbp,
        6 => regs.rsi,
        7 => regs.rdi,
        else => unreachable,
    };
    return switch (size) {
        .bits8 => if (id.highByte()) (val >> 8) & 0xFF else val & 0xFF,
        .bits16 => val & 0xFFFF,
        .bits32 => val & 0xFFFFFFFF,
        .bits64 => val,
    };
}

pub fn setReg(regs: *Regs, id: RegId, size: OperandSize, val: u64) void {
    const r = @as(u64, @intFromEnum(id));
    const old: u64 = switch (r) {
        0 => regs.rax,
        1 => regs.rcx,
        2 => regs.rdx,
        3 => regs.rbx,
        4 => regs.rsp,
        5 => regs.rbp,
        6 => regs.rsi,
        7 => regs.rdi,
        else => unreachable,
    };
    const new = switch (size) {
        .bits8 => if (id.highByte()) (old & 0xFFFF_FFFF_FFFF_00FF) | ((val & 0xFF) << 8) else (old & 0xFFFF_FFFF_FFFF_FF00) | (val & 0xFF),
        .bits16 => (old & 0xFFFF_FFFF_FFFF_0000) | (val & 0xFFFF),
        .bits32 => val & 0xFFFFFFFF,
        .bits64 => val,
    };
    switch (r) {
        0 => regs.rax = new,
        1 => regs.rcx = new,
        2 => regs.rdx = new,
        3 => regs.rbx = new,
        4 => regs.rsp = new,
        5 => regs.rbp = new,
        6 => regs.rsi = new,
        7 => regs.rdi = new,
        else => unreachable,
    }
}

test "32-bit register writes zero-extend into 64-bit parent" {
    var regs = Regs{ .rax = 0xffff_ffff_ffff_ffff };
    setReg(&regs, .al_ax_eax_rax, .bits32, 0x1234);
    try @import("std").testing.expectEqual(@as(u64, 0x1234), regs.rax);
}
