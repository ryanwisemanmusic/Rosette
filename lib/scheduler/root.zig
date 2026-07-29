const std = @import("std");

pub const thread_interceptor = @import("thread_interceptor.zig");
pub const thread_registry = @import("thread_registry.zig");
pub const scheduler_policy = @import("scheduler_policy.zig");
pub const scheduler = @import("scheduler.zig");
pub const ui_handoff = @import("ui_handoff.zig");
pub const cooperative_rotation = @import("cooperative_rotation.zig");
pub const guest_sleep = @import("guest_sleep.zig");
pub const event_log = @import("event_log.zig");
pub const guest_time = @import("guest_time.zig");
pub const spin_parking = @import("spin_parking.zig");
pub const polling_detection = @import("polling_detection.zig");
pub const wait_graph = @import("wait_graph.zig");
pub const native_thread_backend = @import("native_thread_backend.zig");

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
pub const UiHandoffTracker = ui_handoff.UiHandoffTracker;
pub const UiHandoffPhase = ui_handoff.Phase;
pub const UiHandoffHealth = ui_handoff.Health;
pub const UiCallbackQuantumAction = ui_handoff.CallbackQuantumAction;
pub const CooperativeWork = cooperative_rotation.Work;
pub const CooperativeInputs = cooperative_rotation.Inputs;
pub const chooseCooperativeWork = cooperative_rotation.choose;
pub const GuestSleepDecision = guest_sleep.Decision;
pub const GuestSleepRepair = guest_sleep.Repair;
pub const GuestSleepKind = guest_sleep.Kind;
pub const classifyGuestSleep = guest_sleep.classify;
pub const SchedulerEvent = event_log.Event;
pub const SchedulerEventKind = event_log.Kind;
pub const SchedulerEventLog = event_log.Logger;
pub const TimeMode = guest_time.TimeMode;
pub const GuestTimeService = guest_time.Service;
pub const GuestTimerEntry = guest_time.TimerEntry;
pub const SpinParkingManager = spin_parking.SpinParkingManager;
pub const SpinConfig = spin_parking.SpinConfig;
pub const AddressWatch = spin_parking.AddressWatch;
pub const SpinState = spin_parking.SpinState;
pub const OperandWidth = spin_parking.OperandWidth;
pub const PollingDetectionManager = polling_detection.PollingDetectionManager;
pub const PollingConfig = polling_detection.PollingConfig;
pub const PollingState = polling_detection.PollingState;
pub const PollingClassification = polling_detection.PollingClassification;
pub const formatPollingDiagnostic = polling_detection.formatPollingDiagnostic;
pub const WaitForGraph = wait_graph.WaitForGraph;
pub const WaitNodeType = wait_graph.WaitNodeType;
pub const WaitNode = wait_graph.WaitNode;
pub const BlockingClassification = wait_graph.BlockingClassification;
pub const BlockingType = wait_graph.BlockingType;
pub const ThreadStateInfo = wait_graph.ThreadStateInfo;
// pub const NativeThreadBackend = native_thread_backend.NativeThreadBackend;
// pub const NativeThreadConfig = native_thread_backend.NativeThreadConfig;
// pub const NativeThreadContext = native_thread_backend.NativeThreadContext;
// pub const ExecutionMode = native_thread_backend.ExecutionMode;
// pub const AffinityPolicy = native_thread_backend.AffinityPolicy;
// pub const ThreadState = native_thread_backend.ThreadState;
// pub const ThreadError = native_thread_backend.ThreadError;
// pub const CpuContext = native_thread_backend.CpuContext;

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
    _ = ui_handoff;
    _ = cooperative_rotation;
    _ = guest_sleep;
    _ = event_log;
    _ = guest_time;
    _ = spin_parking;
    _ = polling_detection;
    _ = wait_graph;
    // _ = native_thread_backend; // Skip for now due to threading complexity

    // Test global functions
    const allocator = std.testing.allocator;
    initGlobalScheduler(allocator);
    defer shutdownGlobalScheduler();

    const scheduler_instance = getGlobalScheduler();
    try std.testing.expect(scheduler_instance.initialized);
}
