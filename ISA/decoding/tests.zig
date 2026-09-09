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
const coverage = @import("coverage.zig");
const twobyte = @import("twobyte.zig");
const vex = @import("vex.zig");
const groups = @import("groups.zig");

test "legacy MOV decodes the register form used by the Windows message loop" {
    // Win32WindowedAppContext::RunMainMessageLoop contains `mov ebx, eax`
    // (89 C3). Keep this exact ModR/M form in the shared decoder contract so
    // a production decoder regression cannot hide behind the broader MOV
    // family tests.
    const decoded = legacy.decodeLegacyInstruction(
        &[_]u8{ 0x89, 0xC3, 0x8D, 0x43, 0x01 },
        .long64,
    );
    try std.testing.expectEqual(types.Op.mov_reg32_reg32, decoded.op);
    try std.testing.expectEqual(types.RegId.bl_bx_ebx_rbx, decoded.dst_reg);
    try std.testing.expectEqual(types.RegId.al_ax_eax_rax, decoded.src_reg);
    try std.testing.expectEqual(@as(u8, 2), decoded.len);
    try std.testing.expect(decoded.is_reg_form);
}

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

test "VEX2 VSHUFPD decodes its mandatory 66 packed-double form" {
    const decoded = vex.decodeVex2(&[_]u8{ 0xC5, 0xF9, 0xC6, 0xC8, 0x01 }, 0);
    try std.testing.expectEqual(types.Op.vshufpd, decoded.op);
    try std.testing.expectEqual(@as(u8, 1), decoded.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), decoded.xmm_src2);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expect(decoded.uses_imm);
    try std.testing.expectEqual(@as(u8, 5), decoded.len);

    const dispatched = legacy.decodeLegacyInstruction(&[_]u8{ 0xC5, 0xF9, 0xC6, 0xC8, 0x01 }, .long64);
    try std.testing.expectEqual(types.Op.vshufpd, dispatched.op);
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

test "VEX 128-bit lane insertion and extraction preserve operand direction" {
    // VINSERTF128 ymm0, ymm0, xmm1, 0.
    const insert_f = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x18, 0xC1, 0x00 }, 0);
    try std.testing.expectEqual(types.Op.vinsertf128, insert_f.op);
    try std.testing.expectEqual(@as(u8, 0), insert_f.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), insert_f.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), insert_f.xmm_src2);
    try std.testing.expect(insert_f.is_reg_form);
    try std.testing.expectEqual(@as(u64, 0), insert_f.imm);
    try std.testing.expectEqual(@as(u8, 6), insert_f.len);

    // VEXTRACTF128 xmm1, ymm0, 1. The source is ModRM.reg and the
    // destination is ModRM.r/m; a generic NDS decoder would swap these.
    const extract_f = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x19, 0xC1, 0x01 }, 0);
    try std.testing.expectEqual(types.Op.vextractf128, extract_f.op);
    try std.testing.expectEqual(@as(u8, 0), extract_f.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), extract_f.xmm_dst);
    try std.testing.expect(extract_f.is_reg_form);
    try std.testing.expectEqual(@as(u64, 1), extract_f.imm);

    // VINSERTI128 uses the same lane semantics with the AVX2 opcode 38.
    const insert_i = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x38, 0xC1, 0x01 }, 0);
    try std.testing.expectEqual(types.Op.vinserti128, insert_i.op);
    try std.testing.expectEqual(@as(u8, 0), insert_i.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), insert_i.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), insert_i.xmm_src2);
    try std.testing.expectEqual(@as(u64, 1), insert_i.imm);
}

test "VEX integer lane alias, two-source permutation, and min-position decode" {
    // VEXTRACTI128 xmm1, ymm0, 1. The integer opcode is normalized to the
    // same bitwise lane executor used by VEXTRACTF128.
    const extract_i = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x39, 0xC1, 0x01 }, 0);
    try std.testing.expectEqual(types.Op.vextractf128, extract_i.op);
    try std.testing.expectEqual(@as(u8, 0), extract_i.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), extract_i.xmm_dst);
    try std.testing.expect(extract_i.is_reg_form);
    try std.testing.expectEqual(@as(u64, 1), extract_i.imm);
    try std.testing.expectEqual(@as(u8, 6), extract_i.len);

    // VPERM2F128 ymm0, ymm2, ymm1, 0x1B.
    const permute = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x6D, 0x06, 0xC1, 0x1B }, 0);
    try std.testing.expectEqual(types.Op.vperm2f128, permute.op);
    try std.testing.expectEqual(@as(u8, 0), permute.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), permute.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), permute.xmm_src2);
    try std.testing.expect(permute.is_reg_form);
    try std.testing.expect(permute.vector_256);
    try std.testing.expectEqual(@as(u64, 0x1B), permute.imm);
    try std.testing.expectEqual(@as(u8, 6), permute.len);

    // VPHMINPOSUW xmm0, xmm1. VEX.vvvv is reserved and must not become SRC2.
    const min_position = vex.decodeVex3(&[_]u8{ 0xC4, 0xE2, 0x79, 0x41, 0xC1 }, 0);
    try std.testing.expectEqual(types.Op.vphminposuw, min_position.op);
    try std.testing.expectEqual(@as(u8, 0), min_position.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), min_position.xmm_src);
    try std.testing.expect(min_position.is_reg_form);
    try std.testing.expect(!min_position.vector_256);
    try std.testing.expectEqual(@as(u8, 5), min_position.len);
}

test "VPSHUFLW and VPSHUFHW decode in both VEX forms" {
    // The mandatory-prefix mapping is intentionally explicit here: pp=11b is
    // F2 (low words), while pp=10b is F3 (high words). VEX.vvvv is reserved
    // and therefore encoded as 1111 in both forms.
    const low_two = [_]u8{ 0xC5, 0xFB, 0x70, 0xC1, 0x1B };
    const high_two = [_]u8{ 0xC5, 0xFA, 0x70, 0xC1, 0x1B };
    try std.testing.expectEqual(types.Op.vpshuflw, vex.decodeVex2(&low_two, 0).op);
    try std.testing.expectEqual(types.Op.vpshufhw, vex.decodeVex2(&high_two, 0).op);
    try std.testing.expectEqual(types.Op.vpshuflw, legacy.decodeLegacyInstruction(&low_two, .long64).op);
    try std.testing.expectEqual(types.Op.vpshufhw, legacy.decodeLegacyInstruction(&high_two, .long64).op);

    const low_three = [_]u8{ 0xC4, 0xE1, 0x7B, 0x70, 0xC1, 0x1B };
    const high_three = [_]u8{ 0xC4, 0xE1, 0x7A, 0x70, 0xC1, 0x1B };
    try std.testing.expectEqual(types.Op.vpshuflw, vex.decodeVex3(&low_three, 0).op);
    try std.testing.expectEqual(types.Op.vpshufhw, vex.decodeVex3(&high_three, 0).op);
    try std.testing.expectEqual(@as(u8, 1), vex.decodeVex3(&low_three, 0).xmm_src);
    try std.testing.expectEqual(@as(u64, 0x1B), vex.decodeVex3(&low_three, 0).imm);

    // Encoded vvvv != 1111 is reserved for these unary forms; accepting it
    // would turn malformed bytes into a valid instruction with a phantom
    // source register.
    try std.testing.expectEqual(types.Op.invalid, vex.decodeVex2(&[_]u8{ 0xC5, 0xF3, 0x70, 0xC1, 0x1B }, 0).op);
}

test "VMASKMOV and VPALIGNR decode their distinct VEX operand roles" {
    // VEX.256.66.0F38.2C /r: VMASKMOVPS ymm0, ymm1, [rcx]. The mask is
    // VEX.vvvv, while ModRM.reg is the load destination.
    const mask_load = [_]u8{ 0xC4, 0xE2, 0x75, 0x2C, 0x01 };
    const decoded_load = vex.decodeVex3(&mask_load, 0);
    try std.testing.expectEqual(types.Op.vmaskmovps_load, decoded_load.op);
    try std.testing.expectEqual(@as(u8, 0), decoded_load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), decoded_load.xmm_src);
    try std.testing.expect(!decoded_load.is_reg_form);
    try std.testing.expect(decoded_load.vector_256);
    try std.testing.expectEqual(@as(u8, 5), decoded_load.len);

    // VEX.256.66.0F38.2F /r: VMASKMOVPD [rcx], ymm0, ymm1. Stores reverse
    // the data/mask roles but retain the same VEX.vvvv mask encoding.
    const mask_store = [_]u8{ 0xC4, 0xE2, 0x75, 0x2F, 0x01 };
    const decoded_store = vex.decodeVex3(&mask_store, 0);
    try std.testing.expectEqual(types.Op.vmaskmovpd_store, decoded_store.op);
    try std.testing.expectEqual(@as(u8, 0), decoded_store.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), decoded_store.xmm_src2);
    try std.testing.expect(!decoded_store.is_reg_form);
    try std.testing.expect(decoded_store.vector_256);
    try std.testing.expectEqual(@as(u8, 5), decoded_store.len);

    // The register form is reserved for VMASKMOV and must not be accepted as
    // a normal vector operation with an accidental register-to-register path.
    try std.testing.expectEqual(
        types.Op.invalid,
        vex.decodeVex3(&[_]u8{ 0xC4, 0xE2, 0x75, 0x2C, 0xC1 }, 0).op,
    );

    // V PALIGNR is NDS: VEX.vvvv is SRC1 and ModRM.r/m is SRC2. The known
    // AVX2 encoding is vpalignr ymm2, ymm6, ymm4, 7.
    const align_bytes = [_]u8{ 0xC4, 0xE3, 0x4D, 0x0F, 0xD4, 0x07 };
    const decoded_align = vex.decodeVex3(&align_bytes, 0);
    try std.testing.expectEqual(types.Op.vpalignr, decoded_align.op);
    try std.testing.expectEqual(@as(u8, 2), decoded_align.xmm_dst);
    try std.testing.expectEqual(@as(u8, 6), decoded_align.xmm_src);
    try std.testing.expectEqual(@as(u8, 4), decoded_align.xmm_src2);
    try std.testing.expect(decoded_align.is_reg_form);
    try std.testing.expect(decoded_align.vector_256);
    try std.testing.expectEqual(@as(u64, 7), decoded_align.imm);
    try std.testing.expectEqual(@as(u8, 6), decoded_align.len);
}

test "VPUNPCK unpack family decodes in both VEX forms with correct opcodes" {
    // The unpack family spans 66.0F 60-6D: LBW/LWD/LDQ at 60-62, HBW/HWD/HDQ
    // at 68-6A, LQDQ at 6C, HQDQ at 6D. Regression: 0x6D (VPUNPCKHQDQ) was
    // absent from both decodeVex2 and decodeVex3, so the op had an execution
    // arm it could never reach and any byte sequence it should decode fell
    // through as invalid; and the test-only decodeVexInstruction table mapped
    // 0x68/0x69 to the qword ops and 0x64-0x66 to unpack instead of the
    // packed compares, contradicting Intel SDM and the x86 .inc tables.
    const two_byte = [_]struct { bytes: [4]u8, want: types.Op }{
        .{ .bytes = .{ 0xC5, 0xF9, 0x60, 0xC1 }, .want = .vpunpcklbw },
        .{ .bytes = .{ 0xC5, 0xF9, 0x61, 0xC1 }, .want = .vpunpcklwd },
        .{ .bytes = .{ 0xC5, 0xF9, 0x68, 0xC1 }, .want = .vpunpckhbw },
        .{ .bytes = .{ 0xC5, 0xF9, 0x69, 0xC1 }, .want = .vpunpckhwd },
        .{ .bytes = .{ 0xC5, 0xF9, 0x6A, 0xC1 }, .want = .vpunpckhdq },
        .{ .bytes = .{ 0xC5, 0xF9, 0x6C, 0xC1 }, .want = .vpunpcklqdq },
        .{ .bytes = .{ 0xC5, 0xF9, 0x6D, 0xC1 }, .want = .vpunpckhqdq },
    };
    for (two_byte) |c| {
        const decoded = vex.decodeVex2(&c.bytes, 0);
        try std.testing.expectEqual(c.want, decoded.op);
        // Both sources are live: VEX.vvvv lands in xmm_src, ModRM.rm in xmm_src2.
        try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    }

    const three_byte = [_]struct { bytes: [5]u8, want: types.Op }{
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x60, 0xC1 }, .want = .vpunpcklbw },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x61, 0xC1 }, .want = .vpunpcklwd },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x68, 0xC1 }, .want = .vpunpckhbw },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x69, 0xC1 }, .want = .vpunpckhwd },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x6A, 0xC1 }, .want = .vpunpckhdq },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x6C, 0xC1 }, .want = .vpunpcklqdq },
        .{ .bytes = .{ 0xC4, 0xE1, 0x79, 0x6D, 0xC1 }, .want = .vpunpckhqdq },
    };
    for (three_byte) |c| {
        const decoded = vex.decodeVex3(&c.bytes, 0);
        try std.testing.expectEqual(c.want, decoded.op);
        try std.testing.expectEqual(@as(u8, 1), decoded.xmm_src2);
    }

    // 0x64-0x66 are the packed signed compares, not unpack ops.
    try std.testing.expectEqual(types.Op.vpcmpgtb, vex.decodeVex2(&[_]u8{ 0xC5, 0xF9, 0x64, 0xC1 }, 0).op);
    try std.testing.expectEqual(types.Op.vpcmpgtw, vex.decodeVex2(&[_]u8{ 0xC5, 0xF9, 0x65, 0xC1 }, 0).op);
    try std.testing.expectEqual(types.Op.vpcmpgtd, vex.decodeVex2(&[_]u8{ 0xC5, 0xF9, 0x66, 0xC1 }, 0).op);
}

test "VEX operand roles cover arithmetic moves and scalar lane forms" {
    // VPSUBD xmm3, xmm2, xmm1: VEX.vvvv is SRC1 and ModR/M.r/m is SRC2.
    const sub = vex.decodeVex2(&[_]u8{ 0xC5, 0xE9, 0xFA, 0xD9 }, 0);
    try std.testing.expectEqual(types.Op.vpsubd, sub.op);
    try std.testing.expectEqual(@as(u8, 3), sub.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), sub.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), sub.xmm_src2);

    // VMOVDQA xmm2, xmm3 in the register-form store encoding. The ModR/M
    // direction is opposite the load form: ModR/M.reg is the source and
    // ModR/M.r/m is the destination.
    const store = vex.decodeVex2(&[_]u8{ 0xC5, 0xF9, 0x7F, 0xDA }, 0);
    try std.testing.expectEqual(types.Op.vmovdqa_xmm_xmm, store.op);
    try std.testing.expectEqual(@as(u8, 2), store.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), store.xmm_src);

    // VROUNDPS xmm0, xmm1, 0: unary VEX form, with VEX.vvvv reserved.
    const round = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x79, 0x08, 0xC1, 0x00 }, 0);
    try std.testing.expectEqual(types.Op.vroundps, round.op);
    try std.testing.expectEqual(@as(u8, 0), round.xmm_dst);
    try std.testing.expectEqual(@as(u8, 1), round.xmm_src);
    try std.testing.expect(round.uses_imm);

    // VPINSRB xmm1, xmm2, eax, 5: the scalar source is a GPR, not xmm0.
    const insert = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x69, 0x20, 0xC8, 0x05 }, 0);
    try std.testing.expectEqual(types.Op.vpinsrb_xmm_xmm_reg32, insert.op);
    try std.testing.expectEqual(@as(u8, 1), insert.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), insert.xmm_src);
    try std.testing.expectEqual(types.RegId.al_ax_eax_rax, insert.src_reg);
    try std.testing.expect(insert.is_reg_form);

    // VPEXTRD ecx, xmm0, 2: the vector source is ModR/M.reg and the GPR
    // destination is ModR/M.r/m.
    const extract = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0x79, 0x16, 0xC1, 0x02 }, 0);
    try std.testing.expectEqual(types.Op.vpextrd, extract.op);
    try std.testing.expectEqual(@as(u8, 0), extract.xmm_src);
    try std.testing.expectEqual(types.RegId.cl_cx_ecx_rcx, extract.dst_reg);
    try std.testing.expect(extract.is_reg_form);

    // VPEXTRQ rbx, xmm0, 2: opcode 16 with VEX.W=1 selects the qword form.
    const extract_q = vex.decodeVex3(&[_]u8{ 0xC4, 0xE3, 0xF9, 0x16, 0xC3, 0x02 }, 0);
    try std.testing.expectEqual(types.Op.vpextrq, extract_q.op);
    try std.testing.expectEqual(@as(u8, 0), extract_q.xmm_src);
    try std.testing.expectEqual(types.RegId.bl_bx_ebx_rbx, extract_q.dst_reg);
    try std.testing.expectEqual(@as(u64, 2), extract_q.imm);
    try std.testing.expect(extract_q.is_reg_form);
}

test "every decoder family analyzes cleanly (refAllDecls)" {
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(coverage);
    std.testing.refAllDecls(prefix);
    std.testing.refAllDecls(addressing);
    std.testing.refAllDecls(cpu);
    std.testing.refAllDecls(legacy);
    std.testing.refAllDecls(twobyte);
    std.testing.refAllDecls(vex);
    std.testing.refAllDecls(groups);
}

// The complete group-1 matrix, decoded from real encodings.
//
// Group 1 is `0x80`/`0x81`/`0x83` with the operation in ModRM.reg, and the
// opcode it produces used to be derived as `@intFromEnum(base) + (size -
// bits8)`. That is only correct while every family declares four contiguous
// members. `sbb` declared one. `48 83 D8 08` (`sbb rax, 8`) therefore indexed
// past its family and resolved to `add_reg64_imm32`: it decoded, it executed,
// and it added — ignoring the borrow and the carry flag — with no diagnostic
// anywhere. A run has no way to notice that.
//
// The mapping is explicit now, and this walks all eight operations across both
// immediate widths, all four operand widths and both destination kinds,
// checking the opcode by name. Deriving the expected name the same way the
// tables do would prove nothing, so the names are spelled out.
test "every group 1 encoding decodes to its own operation" {
    const Case = struct { op: u3, name: []const u8 };
    const cases = [_]Case{
        .{ .op = 0, .name = "add" }, .{ .op = 1, .name = "or" },
        .{ .op = 2, .name = "adc" }, .{ .op = 3, .name = "sbb" },
        .{ .op = 4, .name = "and" }, .{ .op = 5, .name = "sub" },
        .{ .op = 6, .name = "xor" }, .{ .op = 7, .name = "cmp" },
    };

    for (cases) |case| {
        const reg_modrm: u8 = 0xC0 | (@as(u8, case.op) << 3); // mod=11, rm=rax
        const mem_modrm: u8 = 0x40 | (@as(u8, case.op) << 3); // mod=01, rm=[rax+disp8]

        // 0x83: sign-extended imm8, register and memory, 32- and 64-bit.
        {
            const bytes = [_]u8{ 0x83, reg_modrm, 0x08 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg32_imm8");
        }
        {
            const bytes = [_]u8{ 0x48, 0x83, reg_modrm, 0x08 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg64_imm8");
        }
        {
            // The reported failure: `48 83 50 08 00` is `adc qword ptr
            // [rax+8], 0` and decoded as `invalid`.
            const bytes = [_]u8{ 0x48, 0x83, mem_modrm, 0x08, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "mem64_imm8");
            try std.testing.expectEqual(@as(u8, 5), d.len);
        }
        {
            const bytes = [_]u8{ 0x83, mem_modrm, 0x08, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "mem32_imm8");
        }

        // 0x80: byte operand, register and memory.
        {
            const bytes = [_]u8{ 0x80, reg_modrm, 0x08 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg8_imm8");
        }
        {
            const bytes = [_]u8{ 0x80, mem_modrm, 0x08, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "mem8_imm8");
        }

        // 0x81: full-width immediate. The 64-bit form sign-extends imm32.
        {
            const bytes = [_]u8{ 0x81, reg_modrm, 0x39, 0x01, 0x00, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg32_imm32");
            try std.testing.expectEqual(@as(u64, 0x139), d.imm);
        }
        {
            const bytes = [_]u8{ 0x48, 0x81, reg_modrm, 0x39, 0x01, 0x00, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg64_imm32");
        }
        {
            const bytes = [_]u8{ 0x48, 0x81, mem_modrm, 0x08, 0x39, 0x01, 0x00, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "mem64_imm32");
        }
        {
            const bytes = [_]u8{ 0x81, mem_modrm, 0x08, 0x39, 0x01, 0x00, 0x00 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "mem32_imm32");
        }
        {
            const bytes = [_]u8{ 0x66, 0x81, reg_modrm, 0x39, 0x01 };
            const d = legacy.decodeLegacyInstruction(&bytes, .long64);
            try expectOpNamed(d.op, case.name, "reg16_imm32");
        }
    }
}

// `sbb rax, 8`, the encoding that silently added. Kept as its own case so the
// regression is findable by the instruction rather than by the matrix.
test "sbb with a sign-extended byte immediate is a subtraction" {
    const bytes = [_]u8{ 0x48, 0x83, 0xD8, 0x08 };
    const d = legacy.decodeLegacyInstruction(&bytes, .long64);
    try std.testing.expectEqual(types.Op.sbb_reg64_imm8, d.op);
    try std.testing.expectEqual(@as(u64, 8), d.imm);
    try std.testing.expectEqual(types.Size.bits64, d.size);
    try std.testing.expectEqual(@as(u8, 4), d.len);
}

fn expectOpNamed(op: types.Op, family: []const u8, suffix: []const u8) !void {
    var expected: [64]u8 = undefined;
    const want = std.fmt.bufPrint(&expected, "{s}_{s}", .{ family, suffix }) catch unreachable;
    const actual = @tagName(op);
    if (!std.mem.eql(u8, want, actual)) {
        std.debug.print("group 1: expected {s}, decoded {s}\n", .{ want, actual });
        return error.WrongGroup1Opcode;
    }
}

// SHLD/SHRD, both count sources and both destination kinds.
//
// `48 0F A4 D0 20` — `shld rax, rdx, 32` at guest 0x744871 — decoded as
// `invalid` because the whole family was absent: no opcode, no decode, no
// execution. ModRM.reg is the *source* whose bits fill the vacated end, not a
// second destination, so a decoder that treats it like the neighbouring
// `0F A3` bit-test forms gets the operands backwards.
test "double-precision shifts decode with the fill register as the source" {
    // The reported encoding.
    {
        const bytes = [_]u8{ 0x48, 0x0F, 0xA4, 0xD0, 0x20 };
        const d = legacy.decodeLegacyInstruction(&bytes, .long64);
        try std.testing.expectEqual(types.Op.shld_reg_imm8, d.op);
        try std.testing.expectEqual(types.Size.bits64, d.size);
        try std.testing.expectEqual(@as(u64, 32), d.imm);
        try std.testing.expectEqual(@as(u8, 5), d.len);
        // rm=rax is the destination, reg=rdx is the fill source.
        try std.testing.expectEqual(types.RegId.al_ax_eax_rax, d.dst_reg);
        try std.testing.expectEqual(types.RegId.dl_dx_edx_rdx, d.src_reg);
    }

    const Case = struct { opcode: u8, imm: bool, op_reg: types.Op, op_mem: types.Op };
    const cases = [_]Case{
        .{ .opcode = 0xA4, .imm = true, .op_reg = .shld_reg_imm8, .op_mem = .shld_mem_imm8 },
        .{ .opcode = 0xA5, .imm = false, .op_reg = .shld_reg_cl, .op_mem = .shld_mem_cl },
        .{ .opcode = 0xAC, .imm = true, .op_reg = .shrd_reg_imm8, .op_mem = .shrd_mem_imm8 },
        .{ .opcode = 0xAD, .imm = false, .op_reg = .shrd_reg_cl, .op_mem = .shrd_mem_cl },
    };
    for (cases) |case| {
        // Register destination, 32- and 64-bit.
        {
            var bytes = [_]u8{ 0x0F, case.opcode, 0xD0, 0x04 };
            const d = legacy.decodeLegacyInstruction(bytes[0..if (case.imm) 4 else 3], .long64);
            try std.testing.expectEqual(case.op_reg, d.op);
            try std.testing.expectEqual(types.Size.bits32, d.size);
        }
        {
            var bytes = [_]u8{ 0x48, 0x0F, case.opcode, 0xD0, 0x04 };
            const d = legacy.decodeLegacyInstruction(bytes[0..if (case.imm) 5 else 4], .long64);
            try std.testing.expectEqual(case.op_reg, d.op);
            try std.testing.expectEqual(types.Size.bits64, d.size);
        }
        // Memory destination: mod=01 rm=rax with a byte displacement.
        {
            var bytes = [_]u8{ 0x48, 0x0F, case.opcode, 0x50, 0x08, 0x04 };
            const d = legacy.decodeLegacyInstruction(bytes[0..if (case.imm) 6 else 5], .long64);
            try std.testing.expectEqual(case.op_mem, d.op);
            try std.testing.expectEqual(types.Size.bits64, d.size);
        }
        // 16-bit operand through the 0x66 prefix.
        {
            var bytes = [_]u8{ 0x66, 0x0F, case.opcode, 0xD0, 0x04 };
            const d = legacy.decodeLegacyInstruction(bytes[0..if (case.imm) 5 else 4], .long64);
            try std.testing.expectEqual(case.op_reg, d.op);
            try std.testing.expectEqual(types.Size.bits16, d.size);
        }
    }
}

// The opcode-space census lives beside the decoder it measures, so its tests
// run wherever the decoder's do.
test {
    _ = coverage;
}
