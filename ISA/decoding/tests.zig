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
