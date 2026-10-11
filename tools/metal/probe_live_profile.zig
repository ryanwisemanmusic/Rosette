//! Read-only production policy/loader identity checks. No GPU commands.
const std = @import("std");
const policy = @import("policy").metal.live_texture;
pub fn main(init: std.process.Init) !void {
    const a = std.heap.c_allocator;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 6) return error.ExpectedDriverAndFourLoaders;
    const driver = try a.dupeZ(u8, args[1]);
    defer a.free(driver);
    const lib = std.c.dlopen(driver, @bitCast(@as(u32, 0x1))) orelse return error.DriverUnavailable;
    defer _ = std.c.dlclose(lib);
    if (policy.resolveControl(null, 14, 10207, 256) == null) return error.NativeProfileUnavailable;
    if (policy.resolveControl(null, 14, 10208, 256) != null or policy.resolveControl(null, 1, 10207, 256) != null) return error.UnpinnedProfileAccepted;
    const expected = [_]policy.Format{ .ctx1, .dxt1, .dxt3, .dxt5 };
    for (args[2..], expected) |path, format| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(1 << 20));
        defer a.free(bytes);
        if (policy.identify(bytes) != format) return error.LoaderIdentityMismatch;
        bytes[bytes.len - 1] ^= 1;
        if (policy.identify(bytes) != null) return error.MutatedLoaderAccepted;
        std.debug.print("PASS production identity {s}, changed byte refused\n", .{@tagName(format)});
    }
    std.debug.print("PASS production loaded-image control, unpinned profiles refused; no GPU submission\n", .{});
}
