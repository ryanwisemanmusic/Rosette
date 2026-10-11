//! Narrow compatibility for Xenia's unimplemented native XMutant backing.
//!
//! Xenia's InitializeNative leaves `mutant_` empty. Its ReleaseMutant method
//! then calls `mutant_->Release()` without a null check. The caller's machine
//! code maps a false result to X_STATUS_MUTANT_NOT_OWNED, so this helper only
//! admits that exact call site and exact call instruction.

const std = @import("std");

const demangled_name = "xe::kernel::XMutant::ReleaseMutant";
const mangled_name = "_ZN2xe6kernel7XMutant13ReleaseMutantEjbb";
const release_call_offset: u64 = 0x2a;
const release_call_tail = [_]u8{
    0xff, 0x50, 0x18, // call qword ptr [rax + 0x18]
    0x31, 0xc9, // xor ecx, ecx
    0x84, 0xc0, // test al, al
    0xb8, 0x46, 0x00, 0x00, 0xc0, // X_STATUS_MUTANT_NOT_OWNED
    0x0f, 0x45, 0xc1, // cmovne eax, ecx
    0x48,
};

pub fn shouldReturnNotOwned(
    symbol_name: []const u8,
    symbol_offset: u64,
    instruction: []const u8,
    effective_address: u64,
    base_is_rax: bool,
    base_value: u64,
) bool {
    const known_symbol = std.mem.eql(u8, symbol_name, demangled_name) or
        std.mem.eql(u8, symbol_name, mangled_name);
    return known_symbol and
        symbol_offset == release_call_offset and
        instruction.len >= release_call_tail.len and
        std.mem.eql(u8, instruction[0..release_call_tail.len], &release_call_tail) and
        effective_address == 0x18 and
        base_is_rax and base_value == 0;
}

test "only Xenia's exact null XMutant release call is admitted" {
    const call = release_call_tail;
    try std.testing.expect(shouldReturnNotOwned(demangled_name, 0x2a, &call, 0x18, true, 0));
    try std.testing.expect(shouldReturnNotOwned(mangled_name, 0x2a, &call, 0x18, true, 0));
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x29, &call, 0x18, true, 0));
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x2a, &call, 0x18, true, 1));
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x2a, &call, 0x19, true, 0));
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x2a, &call, 0x18, false, 0));
    try std.testing.expect(!shouldReturnNotOwned("other::ReleaseMutant", 0x2a, &call, 0x18, true, 0));
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x2a, &.{ 0xff, 0x50, 0x10 }, 0x18, true, 0));
    var changed_tail = call;
    changed_tail[9] = 1;
    try std.testing.expect(!shouldReturnNotOwned(demangled_name, 0x2a, &changed_tail, 0x18, true, 0));
}
