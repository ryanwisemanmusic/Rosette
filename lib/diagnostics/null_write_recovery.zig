const std = @import("std");

/// A one-byte store of the value zero through a near-null address from inside
/// `xe::StringBuffer` is the empty-buffer NUL terminator: `Reset()` and the
/// constructors end with `buffer_[0] = 0`, and when the object's backing
/// pointer member reads zero — a victim of the same bypassing bulk-writer
/// family the object-header clobbers document — the store lands on the zero
/// page. The object's own slots are still valid (the `buffer_offset_ = 0`
/// store in `Reset()` writes them successfully), so skipping the NUL store is
/// a no-op the guest can never observe: the buffer is empty either way, and it
/// self-heals on next use (`Grow()`'s `realloc(NULL, …)` behaves as `malloc`).
///
/// The envelope is deliberately narrow so a *real* null dereference stays
/// terminal with full diagnostics:
///   * the class is pinned to the Itanium-mangled `xe::StringBuffer`
///     (`12StringBuffer` inside `2xe`) — other classes are untouched;
///   * only a store of a **zero** byte matches (a nonzero byte written
///     through a null pointer is data loss, not a terminator, and remains a
///     fault);
///   * only the `mov_mem8_imm8` shape matches — `Reset`/constructor
///     terminator encodings, not `memset` loops or wider stores;
///   * the address must be below the near-null bound.
pub fn isStringBufferNullTerminator(
    symbol: []const u8,
    op: []const u8,
    imm: u64,
    address: u64,
    bytes: u8,
    is_write: bool,
) bool {
    if (!is_write or bytes != 1) return false;
    if (address >= 0x1000) return false;
    if (std.mem.indexOf(u8, symbol, "12StringBuffer") == null) return false;
    return std.mem.eql(u8, op, "mov_mem8_imm8") and imm == 0;
}

test "StringBuffer Reset NUL terminator is the only repairable shape" {
    // The observed casualty: `mov byte ptr [rax], 0` with rax = null buffer_.
    try std.testing.expect(isStringBufferNullTerminator(
        "__ZN2xe12StringBuffer5ResetEv",
        "mov_mem8_imm8",
        0,
        0x0,
        1,
        true,
    ));

    // Same store from the constructor family (mangled C1/C2) is the same
    // terminator write.
    try std.testing.expect(isStringBufferNullTerminator(
        "__ZN2xe12StringBufferC1Em",
        "mov_mem8_imm8",
        0,
        0x0,
        1,
        true,
    ));

    // A nonzero byte through a null buffer is data loss, not a terminator.
    try std.testing.expect(!isStringBufferNullTerminator(
        "__ZN2xe12StringBuffer5ResetEv",
        "mov_mem8_imm8",
        1,
        0x0,
        1,
        true,
    ));

    // A read of the null buffer (e.g. `to_string`'s `std::string(buffer_, …)`)
    // is a different casualty and stays terminal.
    try std.testing.expect(!isStringBufferNullTerminator(
        "__ZN2xe12StringBuffer9to_stringB7v160006Ev",
        "mov_reg64_mem64",
        0,
        0x0,
        8,
        false,
    ));

    // Wider stores, and stores to real addresses, are not the terminator.
    try std.testing.expect(!isStringBufferNullTerminator(
        "__ZN2xe12StringBuffer5ResetEv",
        "mov_mem64_imm32",
        0,
        0x0,
        8,
        true,
    ));
    try std.testing.expect(!isStringBufferNullTerminator(
        "__ZN2xe12StringBuffer5ResetEv",
        "mov_mem8_imm8",
        0,
        0x2000,
        1,
        true,
    ));

    // A different class's NUL store is not covered by this allowance.
    try std.testing.expect(!isStringBufferNullTerminator(
        "__ZN2xe10SomeBuffer5ResetEv",
        "mov_mem8_imm8",
        0,
        0x0,
        1,
        true,
    ));
    try std.testing.expect(!isStringBufferNullTerminator(
        "_memset",
        "mov_mem8_imm8",
        0,
        0x0,
        1,
        true,
    ));
}
