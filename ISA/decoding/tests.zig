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
