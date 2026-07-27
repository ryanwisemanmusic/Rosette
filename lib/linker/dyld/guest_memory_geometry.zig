const std = @import("std");

/// Rosette tracks x86 guest protection and allocation state at 4 KiB
/// granularity. This is deliberately distinct from the page size exposed by
/// Darwin process APIs: file-backed mmap offsets still have to obey the host
/// kernel's VM page size (16 KiB on Apple Silicon).
pub const guest_page_size: u64 = 4 * 1024;
pub const host_vm_page_size: u64 = std.heap.page_size_min;
pub const darwin_sc_pagesize: i32 = 29;

/// Models a Darwin process-level sysconf query. Returning the guest tracking
/// granularity here makes libc derive file offsets that the host mmap syscall
/// cannot accept.
pub fn darwinSysconf(selector: i32) ?u64 {
    return switch (selector) {
        darwin_sc_pagesize => host_vm_page_size,
        else => null,
    };
}

test "guest tracking and Darwin VM page sizes remain separate" {
    try std.testing.expect(std.math.isPowerOfTwo(guest_page_size));
    try std.testing.expect(std.math.isPowerOfTwo(host_vm_page_size));
    try std.testing.expectEqual(@as(u64, 4096), guest_page_size);
    try std.testing.expectEqual(@as(?u64, host_vm_page_size), darwinSysconf(darwin_sc_pagesize));
    try std.testing.expectEqual(@as(?u64, null), darwinSysconf(-1));
}
