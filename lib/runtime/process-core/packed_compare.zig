//! Execution of packed byte/word/dword/qword compares.
//!
//! Legacy SSE writes only the architectural XMM destination; VEX.128 also
//! clears its paired YMM upper half. Keep that distinction alongside the
//! comparison so new legacy compare encodings cannot accidentally take the
//! VEX state transition.

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const macho_core = @import("macho_core");

const DecodedInsn = x64_decoder.DecodedInsn;

pub fn execute(self: anytype, d: DecodedInsn) void {
    const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = macho_core.decoder.applyVexCompare(self.xmm[d.xmm_src], rhs_low, d.op);
    if (d.vector_256) {
        const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = macho_core.decoder.applyVexCompare(self.ymm_hi[d.xmm_src], rhs_high, d.op);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

/// MOVDDUP reads m64 for the legacy form and duplicates one low quadword per
/// 128-bit lane. VEX.128 also clears the paired upper YMM register.
pub fn executeMovddup(self: anytype, d: DecodedInsn) void {
    const low = if (d.is_reg_form)
        std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little)
    else
        self.readMemVal(d.addr, .bits64);
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], low, .little);
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][8..16], low, .little);
    if (d.vector_256) {
        const high = if (d.is_reg_form)
            std.mem.readInt(u64, self.ymm_hi[d.xmm_src][0..8], .little)
        else
            self.readMemVal(d.addr +% 16, .bits64);
        std.mem.writeInt(u64, self.ymm_hi[d.xmm_dst][0..8], high, .little);
        std.mem.writeInt(u64, self.ymm_hi[d.xmm_dst][8..16], high, .little);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

test "packed compare produces byte masks for equal lanes" {
    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    for (0..16) |lane| {
        lhs[lane] = @intCast(lane);
        rhs[lane] = @intCast(lane);
    }
    rhs[7] ^= 0x80;
    const result = macho_core.decoder.applyVexCompare(lhs, rhs, .vpcmpeqb);
    for (0..16) |lane| {
        try std.testing.expectEqual(if (lane == 7) @as(u8, 0) else 0xFF, result[lane]);
    }
}
