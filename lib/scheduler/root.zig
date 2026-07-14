const std = @import("std");

pub const thread_interceptor = @import("thread_interceptor.zig");
pub const thread_registry = @import("thread_registry.zig");
pub const scheduler_policy = @import("scheduler_policy.zig");
pub const scheduler = @import("scheduler.zig");

// Re-export main types for convenience
pub const ThreadCreationLevel = thread_interceptor.ThreadCreationLevel;
pub const ThreadType = thread_interceptor.ThreadType;
pub const SchedulingMode = thread_interceptor.SchedulingMode;
pub const ThreadPriority = thread_interceptor.ThreadPriority;
pub const ThreadLifecycleState = thread_interceptor.ThreadLifecycleState;
pub const StackPolicy = thread_interceptor.StackPolicy;
pub const ThreadCreationContext = thread_interceptor.ThreadCreationContext;
pub const InterceptionResult = thread_interceptor.InterceptionResult;
pub const ThreadEntry = thread_registry.ThreadEntry;
pub const ThreadRegistry = thread_registry.ThreadRegistry;
pub const SchedulingDecision = scheduler_policy.SchedulingDecision;
pub const PolicyConfig = scheduler_policy.PolicyConfig;
pub const SchedulerPolicy = scheduler_policy.SchedulerPolicy;
pub const GlobalScheduler = scheduler.GlobalScheduler;

// Global functions
pub const getGlobalScheduler = scheduler.getGlobalScheduler;
pub const initGlobalScheduler = scheduler.initGlobalScheduler;
pub const shutdownGlobalScheduler = scheduler.shutdownGlobalScheduler;

test "scheduler module integration" {
    // Test that all modules can be imported
    _ = thread_interceptor;
    _ = thread_registry;
    _ = scheduler_policy;
    _ = scheduler;
    
    // Test global functions
    initGlobalScheduler();
    defer shutdownGlobalScheduler();
    
    const scheduler_instance = getGlobalScheduler();
    try std.testing.expect(scheduler_instance.initialized);
}
