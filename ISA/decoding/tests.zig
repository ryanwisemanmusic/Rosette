//! Aggregated test root for the ISA/decoding family files.
//!
//! Each family file carries its own `test` blocks (13 total).  Because the
//! decoder module is consumed via `-M` deps (whose test blocks do not run
//! under `zig test -Mroot=...`), this root imports every family file directly
//! so those tests execute under `zig build check`, and forces full analysis
//! of each family's public surface with `refAllDecls`.

const std = @import("std");

// Runtime ABI handshake exports required by the runtime_abi_handshake module
// (mirrors src/x64-ASM/decoder_test_root.zig).
pub export fn rosette_debug_enabled() c_int {
    return 0;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return "".ptr;
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 0;
}

const types = @import("types.zig");
const prefix = @import("prefix.zig");
const addressing = @import("addressing.zig");
const cpu = @import("cpu.zig");
const legacy = @import("legacy.zig");
const twobyte = @import("twobyte.zig");
const vex = @import("vex.zig");
const groups = @import("groups.zig");

// The two VEX prefixes are not two instruction sets. A two-byte VEX is exactly
// a three-byte VEX with R unextended, X and B unused, the 0F map and W=0 — so
// `C5 b …` and `C4 E1 (b & 0x7F) …` must decode to the same instruction, and
// any opcode only one of them knows is a latent invalid-instruction crash.
//
// It is latent because which form a compiler emits is a register-allocation
// detail: the short form cannot reach xmm8 and above, so the long form appears
// the first time a hot loop spills into a high register and not before. That is
// exactly how `vucomisd xmm8, xmm8` — Xenia's NaN check — killed a run after
// six billion instructions, while the same comparison on xmm0 had been decoding
// for the entire startup.
//
// Sweeping it is cheap and turns "wait for a crash" into a build failure.
test "the two-byte and three-byte VEX forms decode the same 0F opcodes" {
    const legacy_decode = legacy.decodeLegacyInstruction;
    var gaps: usize = 0;
    for (0..256) |opcode_index| {
        const opcode: u8 = @intCast(opcode_index);
        for ([_]u8{ 0, 1, 2, 3 }) |pp| {
            for ([_]u8{ 0, 4 }) |l| {
                // vvvv left unused (1111) so the encoding is legal for both
                // two- and three-operand forms.
                const control: u8 = (0x0F << 3) | l | pp;
                // Sweep ModRM.reg as well as the opcode. For a *group* opcode
                // — 0F 71/72/73 and friends — the instruction is selected by
                // ModRM.reg, not by the opcode byte, so a fixed ModRM tests one
                // arbitrary member of the group and silently skips the rest.
                // That is exactly how the immediate-count packed shifts stayed
                // missing from the three-byte path: with reg=0 both forms
                // agreed on rejecting a group member that does not exist, and
                // the real members were never encoded.
                for (0..8) |reg| {
                    const modrm: u8 = 0xC1 | (@as(u8, @intCast(reg)) << 3);
                    const two_byte = [_]u8{ 0xC5, 0x80 | control, opcode, modrm, 0, 0, 0, 0, 0x0F };
                    const three_byte = [_]u8{ 0xC4, 0xE1, control, opcode, modrm, 0, 0, 0, 0, 0x0F };
                    const short_form = legacy_decode(&two_byte, .long64);
                    const long_form = legacy_decode(&three_byte, .long64);
                    if (short_form.op == .invalid) continue;
                    if (long_form.op == short_form.op) continue;
                    gaps += 1;
                    std.debug.print(
                        "VEX form mismatch: opcode=0x{X:0>2} pp={d} L={d} modrm_reg={d} two_byte={s} three_byte={s}\n",
                        .{ opcode, pp, l >> 2, reg, @tagName(short_form.op), @tagName(long_form.op) },
                    );
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), gaps);
}

test "three-byte VEX decodes the reported VPMAXSD instruction" {
    const bytes = [_]u8{ 0xC4, 0xE2, 0x71, 0x3D, 0xCA };
    const decoded = vex.decodeVex3(&bytes, 0);
    try std.testing.expectEqual(types.Op.vpmaxsd, decoded.op);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src); // VEX.vvvv
    try std.testing.expectEqual(@as(u8, 2), decoded.xmm_src2); // ModRM.rm
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expect(!decoded.vector_256);
    try std.testing.expectEqual(@as(u8, 5), decoded.len);

    // Exercise the dispatch route used by the processor, not only the VEX
    // helper itself.
    const dispatched = legacy.decodeLegacyInstruction(&bytes, .long64);
    try std.testing.expectEqual(types.Op.vpmaxsd, dispatched.op);
}

test "VEX packed arithmetic shifts decode in both the C5 and C4 forms" {
    // Regression: `C5 F1 E2 CC` (VPSRAD xmm1, xmm1, xmm4) raised SIGILL inside
    // Xenia's shader translator. E1/E2 were absent from *both* VEX opcode
    // tables, which is why the C5-vs-C4 symmetry test above did not catch it:
    // it proves the two paths agree, and they agreed on being wrong. Coverage
    // of a specific encoding needs a test that names the encoding.
    const two_byte = vex.decodeVex2(&[_]u8{ 0xC5, 0xF1, 0xE2, 0xCC }, 0);
    try std.testing.expectEqual(types.Op.vpsrad, two_byte.op);
    try std.testing.expectEqual(@as(u8, 1), two_byte.xmm_dst); // ModRM.reg
    try std.testing.expectEqual(@as(u8, 1), two_byte.xmm_src); // VEX.vvvv
    try std.testing.expectEqual(@as(u8, 4), two_byte.xmm_src2); // ModRM.rm = count
    try std.testing.expect(two_byte.is_reg_form);

    // Same operation through the three-byte form.
    const three_byte = vex.decodeVex3(&[_]u8{ 0xC4, 0xE1, 0x71, 0xE2, 0xCC }, 0);
    try std.testing.expectEqual(types.Op.vpsrad, three_byte.op);
    try std.testing.expectEqual(types.Op.vpsraw, vex.decodeVex2(&[_]u8{ 0xC5, 0xF1, 0xE1, 0xCC }, 0).op);
    try std.testing.expectEqual(types.Op.vpsraw, vex.decodeVex3(&[_]u8{ 0xC4, 0xE1, 0x71, 0xE1, 0xCC }, 0).op);
}

test "VEX immediate shift group 4 is arithmetic, not a left shift" {
    // The immediate form was worse than missing: group 4 fell into an `else`
    // that produced the *left* logical shift, so `vpsraw $3, xmm, xmm` executed
    // as `vpsllw`. A wrong answer, silently, rather than a refused decode.
    const sraw = vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0x71, 0xE2, 0x03 }, 0);
    try std.testing.expectEqual(types.Op.vpsraw, sraw.op);
    try std.testing.expectEqual(@as(u64, 3), sraw.imm);
    try std.testing.expect(sraw.uses_imm);

    const srad = vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0x72, 0xE2, 0x02 }, 0);
    try std.testing.expectEqual(types.Op.vpsrad, srad.op);

    // The neighbouring groups must keep their previous meanings.
    try std.testing.expectEqual(types.Op.vpsrlw, vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0x71, 0xD2, 0x03 }, 0).op);
    try std.testing.expectEqual(types.Op.vpsllw, vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0x71, 0xF2, 0x03 }, 0).op);
    // There is no packed arithmetic quadword shift below AVX-512; group 4 of
    // 0x73 must stay refused rather than aliasing onto vpsllq.
    try std.testing.expectEqual(types.Op.invalid, vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0x73, 0xE2, 0x03 }, 0).op);
}

test "VEX packed min/max decodes through the production three-byte path" {
    // Regression: `C4 E2 71 39 CA` (VPMINSD xmm1, xmm1, xmm2) raised SIGILL in
    // Xenia's shader translator. All eight of 0F38 38..3F had `Op` members and
    // a complete table in `decodeVexMap38` — but `decodeVex3` is what
    // `legacy.zig` calls for a C4 prefix, and it named only 0x3D. A second
    // opcode table that the production path never consults looks exactly like
    // coverage, which is why this test exercises `decodeVex3` specifically.
    const crash = vex.decodeVex3(&[_]u8{ 0xC4, 0xE2, 0x71, 0x39, 0xCA }, 0);
    try std.testing.expectEqual(types.Op.vpminsd, crash.op);
    try std.testing.expectEqual(@as(u8, 1), crash.xmm_dst); // ModRM.reg
    try std.testing.expectEqual(@as(u8, 1), crash.xmm_src); // VEX.vvvv
    try std.testing.expectEqual(@as(u8, 2), crash.xmm_src2); // ModRM.rm
    try std.testing.expect(crash.is_reg_form);

    const expected = [_]types.Op{
        .vpminsb, .vpminsd, .vpminuw, .vpminud,
        .vpmaxsb, .vpmaxsd, .vpmaxuw, .vpmaxud,
    };
    for (expected, 0..) |want, index| {
        const opcode: u8 = @intCast(0x38 + index);
        const decoded = vex.decodeVex3(&[_]u8{ 0xC4, 0xE2, 0x71, opcode, 0xCA }, 0);
        try std.testing.expectEqual(want, decoded.op);
    }
}

test "every decoder family analyzes cleanly (refAllDecls)" {
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(prefix);
    std.testing.refAllDecls(addressing);
    std.testing.refAllDecls(cpu);
    std.testing.refAllDecls(legacy);
    std.testing.refAllDecls(twobyte);
    std.testing.refAllDecls(vex);
    std.testing.refAllDecls(groups);
}
