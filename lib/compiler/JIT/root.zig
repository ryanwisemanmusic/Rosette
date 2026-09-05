const std = @import("std");

pub const types = @import("types.zig");
pub const monitor = @import("monitor.zig");
pub const profiler = @import("profiler.zig");
pub const xenia = @import("xenia.zig");
pub const event_log = @import("event_log.zig");
pub const health = @import("health.zig");

pub const GuestAddress = types.GuestAddress;
pub const HostAddress = types.HostAddress;
pub const JitEventKind = types.JitEventKind;
pub const JitEvent = types.JitEvent;
pub const GuestFunction = types.GuestFunction;
pub const CodeCacheRegion = types.CodeCacheRegion;
pub const ModuleInfo = types.ModuleInfo;
pub const CompileStats = types.CompileStats;

pub const Monitor = monitor.Monitor;
pub const Profiler = profiler.Profiler;

pub const XeniaConstants = xenia.XeniaConstants;
pub const KnownGuestModule = xenia.KnownGuestModule;
pub const SystemVAbi = xenia.SystemVAbi;

pub const JitEventLog = event_log.Logger;
pub const JitEventLogKind = event_log.Kind;
pub const JitLogEvent = event_log.Event;
pub const JitHealth = health.Ledger;
pub const JitHealthSummary = health.Summary;
pub const JitHealthObservation = health.Observation;
pub const JitHealthFinding = health.Finding;
pub const JitHealthEventKind = health.EventKind;

test "JIT types tests" {
    _ = @import("types.zig");
}

test "JIT monitor tests" {
    _ = @import("monitor.zig");
}

test "JIT profiler tests" {
    _ = @import("profiler.zig");
}

test "JIT xenia tests" {
    _ = @import("xenia.zig");
}

test "JIT event_log tests" {
    _ = @import("event_log.zig");
}

test "JIT health tests" {
    _ = @import("health.zig");
}
