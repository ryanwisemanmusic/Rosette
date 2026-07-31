const decoder = @import("x64_decoder");
const std = @import("std");

pub export fn rosette_debug_enabled() c_int {
    return 0;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return "".ptr;
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 0;
}

test "load x64 decoder ABI audit" {
    _ = decoder.Op;
}

test "refAllDecls forces analysis of every decoder declaration" {
    std.testing.refAllDecls(decoder);
}
