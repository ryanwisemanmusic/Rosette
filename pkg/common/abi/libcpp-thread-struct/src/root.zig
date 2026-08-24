//! Static layout facts for libc++'s `std::__1::__thread_struct`.
//!
//! The current Darwin libc++ declaration stores one pointer:
//!
//!     class __thread_struct { __thread_struct_imp* __p_; ... };
//!
//! Its constructor is intercepted by Rosette because guest pthread scheduling
//! is owned by the runtime. The size and alignment belong here as build-time
//! ABI facts; the decision to zero guest memory belongs in lib.

const std = @import("std");

pub const guest_abi = "sysv-x86_64";
pub const host_platform = "darwin";

pub const Layout = struct {
    size: u64,
    alignment: u64,
    pointer_offset: u64,
};

/// `__thread_struct_imp* __p_` is the sole data member on the supported
/// Darwin libc++ ABI. Keep this explicit rather than deriving it from a host
/// C header: the guest object is an x86-64 ABI object even when Rosette is
/// built on ARM64.
pub const layout = Layout{
    .size = 8,
    .alignment = 8,
    .pointer_offset = 0,
};

pub const storage_size = layout.size;
pub const storage_alignment = layout.alignment;

comptime {
    if (@sizeOf(usize) != storage_size) {
        @compileError("libc++ __thread_struct contract requires a 64-bit build");
    }
}

test "thread struct layout is one pointer" {
    try std.testing.expectEqual(@as(u64, 8), layout.size);
    try std.testing.expectEqual(@as(u64, 8), layout.alignment);
    try std.testing.expectEqual(@as(u64, 0), layout.pointer_offset);
    try std.testing.expectEqual(layout.size, storage_size);
}
