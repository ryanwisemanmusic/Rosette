//! Test root for tooling sources whose local imports intentionally cross a
//! sibling tooling/DOS directory. Keeping the root at `src/tooling` gives Zig
//! one module path that contains those imports while still executing the
//! imported modules' own test declarations.

const std = @import("std");

// DOS-session tests exercise the real loader and memory code, but their
// diagnostic ABI normally resolves against the processor executable. Keep
// this standalone source artifact self-contained with the same benign host
// defaults used by the test harness.
pub export fn rosette_debug_enabled() c_int {
    return 0;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return "source-test.log";
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 0;
}

pub const dos16_loader_bridge = @import("tooling/binary_converter/dos16_loader_bridge.zig");
pub const macos_32_bit_binary = @import("tooling/binary_converter/macos_32_bit_binary.zig");
pub const pe_to_arm64_session = @import("tooling/binary_converter/pe_to_arm64_session.zig");

test {
    std.testing.refAllDecls(@This());
}
