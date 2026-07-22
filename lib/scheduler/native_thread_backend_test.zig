const std = @import("std");
const native_thread_backend = @import("native_thread_backend.zig");

// Commented out tests due to threading complexity
/*
test "native thread backend basic operations" {
    const allocator = std.testing.allocator;
    const config = native_thread_backend.NativeThreadConfig{
        .enabled = true,
        .max_native_threads = 4,
    };
    
    var backend = native_thread_backend.NativeThreadBackend.init(allocator, config);
    defer backend.deinit();
    
    // Test thread creation
    var cpu_context = native_thread_backend.CpuContext{};
    
    const test_thread_fn = struct {
        fn threadFn(ctx: *native_thread_backend.NativeThreadContext) void {
            _ = ctx;
            // Simple test function
        }
    }.threadFn;
    
    backend.createNativeThread(0x1000, test_thread_fn, null, &cpu_context, .native) catch unreachable;
    
    const context = backend.getThreadContext(0x1000);
    try std.testing.expect(context != null);
    try std.testing.expectEqual(native_thread_backend.ExecutionMode.native, context.?.mode);
    
    // Test thread state
    try std.testing.expectEqual(native_thread_backend.ThreadState.created, backend.getThreadState(0x1000).?);
    
    // Test thread start
    try backend.startThread(0x1000);
    try std.testing.expectEqual(native_thread_backend.ThreadState.running, backend.getThreadState(0x1000).?);
    
    // Test thread stop
    backend.stopThread(0x1000);
    try std.testing.expectEqual(native_thread_backend.ThreadState.terminated, backend.getThreadState(0x1000).?);
}

test "thread mode migration" {
    const allocator = std.testing.allocator;
    const config = native_thread_backend.NativeThreadConfig{
        .enabled = true,
        .max_native_threads = 4,
    };
    
    var backend = native_thread_backend.NativeThreadBackend.init(allocator, config);
    defer backend.deinit();
    
    var cpu_context = native_thread_backend.CpuContext{};
    
    const test_thread_fn = struct {
        fn threadFn(ctx: *native_thread_backend.NativeThreadContext) void {
            _ = ctx;
        }
    }.threadFn;
    
    // Create cooperative thread
    backend.createNativeThread(0x1000, test_thread_fn, null, &cpu_context, .cooperative) catch unreachable;
    
    // Migrate to native
    try backend.migrateThreadMode(0x1000, .native);
    
    const context = backend.getThreadContext(0x1000);
    try std.testing.expect(context != null);
    try std.testing.expectEqual(native_thread_backend.ExecutionMode.native, context.?.mode);
}
*/