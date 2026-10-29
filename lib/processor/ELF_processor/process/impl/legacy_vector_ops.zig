//! Legacy SSE and VEX distinctions that are shared by the PE instruction
//! executor without growing its already-large dispatch module.

const process = @import("../../process.zig");
const ElfState = process.ElfState;
const DecodedInsn = process.__ProcessInternals._DecodedInsn;
const RegId = process.__ProcessInternals._RegId;
const Size = process.__ProcessInternals._Size;
const vector_helpers = process.__ProcessInternals._vector_helpers;
const lifecycle = @import("lifecycle.zig");
const std = process.__ProcessInternals._std;

pub fn executePackedCompare(self: *ElfState, d: DecodedInsn) bool {
    switch (d.op) {
        .vpcmpeqb,
        .vpcmpeqw,
        .vpcmpeqd,
        .vpcmpeqq,
        .vpcmpgtb,
        .vpcmpgtw,
        .vpcmpgtd,
        .vpcmpgtq,
        => vector_helpers.executeVexPackedCompare(self, d),
        else => return false,
    }
    return true;
}

pub fn executeMovddup(
    self: *ElfState,
    d: DecodedInsn,
    comptime readMem: fn (*ElfState, u64, Size) u64,
) void {
    const xmm = lifecycle.guestContextField(self, "xmm");
    const ymm_hi = lifecycle.guestContextField(self, "ymm_hi");
    const source_low = if (d.is_reg_form)
        std.mem.readInt(u64, xmm.*[d.xmm_src][0..8], .little)
    else
        readMem(self, d.addr, .bits64);
    std.mem.writeInt(u64, xmm.*[d.xmm_dst][0..8], source_low, .little);
    std.mem.writeInt(u64, xmm.*[d.xmm_dst][8..16], source_low, .little);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form)
            std.mem.readInt(u64, ymm_hi.*[d.xmm_src][0..8], .little)
        else
            readMem(self, d.addr +% 16, .bits64);
        std.mem.writeInt(u64, ymm_hi.*[d.xmm_dst][0..8], source_high, .little);
        std.mem.writeInt(u64, ymm_hi.*[d.xmm_dst][8..16], source_high, .little);
    } else if (!d.legacy_sse) {
        @memset(&ymm_hi.*[d.xmm_dst], 0);
    }
}

pub fn executeInsertElement(
    self: *ElfState,
    d: DecodedInsn,
    comptime regVal: fn (*const ElfState, RegId, Size) u64,
    comptime readMem: fn (*ElfState, u64, Size) u64,
) void {
    const element_bytes: usize = switch (d.op) {
        .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => 1,
        .vpinsrw => 2,
        .vpinsrd => 4,
        .vpinsrq => 8,
        else => unreachable,
    };
    const lane = @as(usize, @intCast(d.imm)) & ((16 / element_bytes) - 1);
    const size: Size = if (d.op == .vpinsrq) .bits64 else .bits32;
    const scalar = if (d.is_reg_form) regVal(self, d.src_reg, size) else readMem(self, d.addr, d.size);
    var result = lifecycle.guestContextField(self, "xmm").*[d.xmm_src];
    switch (element_bytes) {
        1 => result[lane] = @truncate(scalar),
        2 => std.mem.writeInt(u16, result[lane * 2 ..][0..2], @truncate(scalar), .little),
        4 => std.mem.writeInt(u32, result[lane * 4 ..][0..4], @truncate(scalar), .little),
        8 => std.mem.writeInt(u64, result[lane * 8 ..][0..8], scalar, .little),
        else => unreachable,
    }
    lifecycle.guestContextField(self, "xmm").*[d.xmm_dst] = result;
    if (!d.legacy_sse) @memset(&lifecycle.guestContextField(self, "ymm_hi").*[d.xmm_dst], 0);
}
