//! diagnostics — Guest diagnostic and observability library.
//!
//! Consolidates diagnostic throttling, text acceleration, fault classification,
//! backend diagnostics, opaque lifetime recovery, launch argument acceleration,
//! startup observation, logging runtime, and runtime output formatting.
//!
//! Module-level dependencies (provided via build.zig addImport):
//!   - macho_compat_runtime  (used by diagnostic_text_accelerator)
//!   - event_log             (shared logging)

pub const diagnostic_throttle = @import("diagnostic_throttle.zig");
pub const log_repetition = @import("log_repetition.zig");
pub const guest_module_map = @import("guest_module_map.zig");
pub const diagnostic_text_accelerator = @import("diagnostic_text_accelerator.zig");
pub const semantic_fault_classifier = @import("semantic_fault_classifier.zig");
pub const zero_adjudication = @import("zero_adjudication.zig");
pub const control_transfer_classifier = @import("control_transfer_classifier.zig");
pub const x64_backend_diagnostics = @import("x64_backend_diagnostics.zig");
pub const xenia_pipeline_contracts = @import("xenia_pipeline_contracts.zig");
pub const xenia_pipeline = @import("xenia_pipeline.zig");
pub const xenia_gpu_handoff = @import("xenia_gpu_handoff.zig");
pub const bringup_failure = @import("bringup_failure.zig");
pub const deadlock_predictor = @import("deadlock_predictor.zig");
pub const deferred_work = @import("deferred_work.zig");
pub const guest_exception_ledger = @import("guest_exception_ledger.zig");
pub const host_contract_coverage = @import("host_contract_coverage.zig");
pub const indirect_target_audit = @import("indirect_target_audit.zig");
pub const guest_wait_liveness = @import("guest_wait_liveness.zig");
pub const stall_release = @import("stall_release.zig");
pub const sync_object_identity = @import("sync_object_identity.zig");
pub const wait_audit = @import("wait_audit.zig");
pub const xenia_memory_views = @import("xenia_memory_views.zig");
pub const guest_critical_section = @import("guest_critical_section.zig");
pub const event_identity = @import("event_identity.zig");
pub const execution_tracepoints = @import("execution_tracepoints.zig");
pub const anomaly_ledger = @import("anomaly_ledger.zig");
pub const spirv_cross_diagnostics = @import("spirv_cross_diagnostics.zig");
pub const opaque_lifetime_recovery = @import("opaque_lifetime_recovery.zig");
pub const null_write_recovery = @import("null_write_recovery.zig");
pub const launch_argument_accelerator = @import("launch_argument_accelerator.zig");
pub const startup_observer = @import("startup_observer.zig");
pub const logging_runtime = @import("logging_runtime.zig");
pub const runtime_output = @import("runtime_output.zig");
pub const rosette_pkg_log = @import("rosette_pkg_log.zig");

// Rooted in build.zig so these run rather than merely compile: three modules so
// far turned out to have tests that were never executed, and one of them had
// never compiled at all.
test {
    _ = diagnostic_throttle;
    _ = log_repetition;
    _ = semantic_fault_classifier;
    _ = zero_adjudication;
    _ = control_transfer_classifier;
    _ = x64_backend_diagnostics;
    _ = xenia_pipeline_contracts;
    _ = xenia_pipeline;
    _ = xenia_gpu_handoff;
    _ = bringup_failure;
    _ = deadlock_predictor;
    _ = deferred_work;
    _ = guest_exception_ledger;
    _ = host_contract_coverage;
    _ = indirect_target_audit;
    _ = guest_wait_liveness;
    _ = stall_release;
    _ = sync_object_identity;
    _ = wait_audit;
    _ = xenia_memory_views;
    _ = guest_critical_section;
    _ = event_identity;
    _ = execution_tracepoints;
    _ = anomaly_ledger;
    _ = spirv_cross_diagnostics;
    _ = opaque_lifetime_recovery;
    _ = null_write_recovery;
    _ = launch_argument_accelerator;
    _ = startup_observer;
    _ = logging_runtime;
    _ = runtime_output;
    _ = rosette_pkg_log;
}
