//! Parallel guest execution primitives for the PE processor.
//!
//! `lib/concurrency` owns host synchronization primitives. This package owns
//! their PE execution contracts: guest workers, the execution gate, shared
//! counters, and thread-affine Win32 message routing.

pub const execution_gate = @import("execution_gate.zig");
pub const metrics = @import("metrics.zig");
pub const translated_memory_contract = @import("translated_memory_contract.zig");
pub const ui_message_queue = @import("ui_message_queue.zig");
pub const worker = @import("worker.zig");

test {
    _ = execution_gate;
    _ = metrics;
    _ = translated_memory_contract;
    _ = ui_message_queue;
    _ = worker;
}
