const flags = @import("flags");

pub const OperandSize = flags.OperandSize;

pub const Segment = enum(u3) {
    es,
    cs,
    ss,
    ds,
    fs,
    gs,
};

// `extern` here is not about C interop: `Regs` below must have a guaranteed
// field order, and an extern struct may only contain extern-layout fields.
pub const SegmentRegister = extern struct {
    selector: u16 = 0,
    base: u64 = 0,
};

pub const SegmentState = extern struct {
    es: SegmentRegister = .{},
    cs: SegmentRegister = .{},
    ss: SegmentRegister = .{},
    ds: SegmentRegister = .{},
    fs: SegmentRegister = .{},
    gs: SegmentRegister = .{},

    pub fn get(self: *const SegmentState, segment: Segment) SegmentRegister {
        return switch (segment) {
            .es => self.es,
            .cs => self.cs,
            .ss => self.ss,
            .ds => self.ds,
            .fs => self.fs,
            .gs => self.gs,
        };
    }

    pub fn getPtr(self: *SegmentState, segment: Segment) *SegmentRegister {
        return switch (segment) {
            .es => &self.es,
            .cs => &self.cs,
            .ss => &self.ss,
            .ds => &self.ds,
            .fs => &self.fs,
            .gs => &self.gs,
        };
    }
};

pub const RegId = enum(u4) {
    al_ax_eax_rax = 0,
    cl_cx_ecx_rcx = 1,
    dl_dx_edx_rdx = 2,
    bl_bx_ebx_rbx = 3,
    ah_sp_esp_rsp = 4,
    ch_bp_ebp_rbp = 5,
    dh_si_esi_rsi = 6,
    bh_di_edi_rdi = 7,
    r8b_r8w_r8d_r8 = 8,
    r9b_r9w_r9d_r9 = 9,
    r10b_r10w_r10d_r10 = 10,
    r11b_r11w_r11d_r11 = 11,
    r12b_r12w_r12d_r12 = 12,
    r13b_r13w_r13d_r13 = 13,
    r14b_r14w_r14d_r14 = 14,
    r15b_r15w_r15d_r15 = 15,

    pub fn highByte(self: RegId) bool {
        _ = self;
        return false;
    }
};

/// The guest register file.
///
/// F2 (throughput audit): the sixteen GPRs are declared first, in x86 encoding
/// order, and the struct is `extern` so that order is guaranteed rather than
/// merely written down. `regVal`/`setReg` then index them as an array.
///
/// This is a codegen fix, not a style preference. With the previous plain
/// struct, Zig's auto layout reordered the fields (rax at offset 8, rcx at 112,
/// rdx at 88 in the shipped binary), so LLVM could not turn the 16-way switch
/// these accessors used into an indexed load. It emitted a jump table instead:
///
///     adrp/add/adr/ldrb/add ; br x10   <- indirect branch, 16 targets
///
/// The register index differs on nearly every instruction, so that branch
/// mispredicts constantly. `setReg` paid it twice (once to read the old value,
/// once to write back), which made a plain `mov r64, r64` cost three of them.
/// The array form is a single `ldr x8, [x0, w1, uxtw #3]`, and `_execute.execute`
/// alone contained 60 out-of-line calls to `regVal` and 33 to `setReg`.
///
/// The named fields are kept because ~1,800 call sites across the tree read
/// them directly, and because `regs.rsp` says more at a use site than
/// `regs.gpr[4]`. The `comptime` block below is what makes both true at once:
/// it proves each named field sits exactly where its `RegId` says, so a future
/// edit that reorders, retypes, or inserts a field is a compile error rather
/// than a silent misindex of the register file.
pub const Regs = extern struct {
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
    // Architectural reset value. Rosette keeps MXCSR in the shared CPU state
    // so legacy LDMXCSR and VEX VLDMXCSR have one runtime-owned contract.
    mxcsr: u32 = 0x0000_1F80,
    segments: SegmentState = .{},

    /// Number of GPRs addressable through `RegId`. `rip` follows them and is
    /// deliberately outside this window: it is not encodable as a `RegId`, and
    /// an out-of-range index must not silently alias it.
    pub const gpr_count = 16;

    comptime {
        // The layout contract, proved rather than assumed.
        const std = @import("std");
        const names = [gpr_count][]const u8{
            "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
            "r8",  "r9",  "r10", "r11", "r12", "r13", "r14", "r15",
        };
        for (names, 0..) |name, index| {
            if (@offsetOf(Regs, name) != index * @sizeOf(u64)) {
                @compileError("Regs GPR layout broken: " ++ name ++ " is not at its RegId index");
            }
        }
        // `RegId` must enumerate exactly those slots, in that order.
        const fields = @typeInfo(RegId).@"enum".fields;
        if (fields.len != gpr_count) @compileError("RegId no longer has 16 members");
        for (fields, 0..) |field, index| {
            if (field.value != index) @compileError("RegId values are no longer 0..15 in order");
        }
        std.debug.assert(@offsetOf(Regs, "rip") == gpr_count * @sizeOf(u64));
    }

    /// The GPRs as a flat array. Sound because the fields above are the first
    /// `gpr_count` members of an `extern` struct of `u64`, which the `comptime`
    /// block proves.
    pub inline fn gprs(self: *Regs) *[gpr_count]u64 {
        return @ptrCast(self);
    }

    pub inline fn gprsConst(self: *const Regs) *const [gpr_count]u64 {
        return @ptrCast(self);
    }

    pub fn get(self: *const Regs, comptime reg: []const u8) u64 {
        _ = self;
        _ = reg;
        return 0;
    }
};

pub inline fn regVal(regs: *const Regs, id: RegId, size: OperandSize) u64 {
    const val = regs.gprsConst()[@intFromEnum(id)];
    return switch (size) {
        .bits8 => if (id.highByte()) (val >> 8) & 0xFF else val & 0xFF,
        .bits16 => val & 0xFFFF,
        .bits32 => val & 0xFFFFFFFF,
        .bits64 => val,
    };
}

pub inline fn setReg(regs: *Regs, id: RegId, size: OperandSize, val: u64) void {
    const slot = &regs.gprs()[@intFromEnum(id)];
    slot.* = switch (size) {
        .bits8 => if (id.highByte())
            (slot.* & 0xFFFF_FFFF_FFFF_00FF) | ((val & 0xFF) << 8)
        else
            (slot.* & 0xFFFF_FFFF_FFFF_FF00) | (val & 0xFF),
        .bits16 => (slot.* & 0xFFFF_FFFF_FFFF_0000) | (val & 0xFFFF),
        .bits32 => val & 0xFFFFFFFF,
        .bits64 => val,
    };
}

test "32-bit register writes zero-extend into 64-bit parent" {
    var regs = Regs{ .rax = 0xffff_ffff_ffff_ffff };
    setReg(&regs, .al_ax_eax_rax, .bits32, 0x1234);
    try @import("std").testing.expectEqual(@as(u64, 0x1234), regs.rax);
}

test "extended registers preserve independent storage" {
    var regs = Regs{};
    setReg(&regs, .r12b_r12w_r12d_r12, .bits64, 0x1122_3344_5566_7788);
    setReg(&regs, .r15b_r15w_r15d_r15, .bits32, 0xaabb_ccdd);
    try @import("std").testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), regVal(&regs, .r12b_r12w_r12d_r12, .bits64));
    try @import("std").testing.expectEqual(@as(u64, 0xaabb_ccdd), regs.r15);
}
