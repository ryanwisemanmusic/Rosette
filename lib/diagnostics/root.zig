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
pub const xenia_gpu_causal_trace = @import("xenia_gpu_causal_trace.zig");
pub const graphics_health_contract = @import("graphics_health_contract.zig");
pub const application_controller = @import("application_controller.zig");
pub const xenia_pm4_walk = @import("xenia_pm4_walk.zig");
pub const bringup_failure = @import("bringup_failure.zig");
pub const run_horizon = @import("run_horizon.zig");
pub const claim_reconciliation = @import("claim_reconciliation.zig");
pub const interrupt_callback_transaction = @import("interrupt_callback_transaction.zig");
pub const async_log = @import("async_log.zig");
pub const translation_economics = @import("translation_economics.zig");
pub const run_integrity = @import("run_integrity.zig");
pub const substantiation = @import("substantiation.zig");
pub const guest_log_channels = @import("guest_log_channels.zig");
pub const wait_graph = @import("wait_graph.zig");
pub const mandatory_order = @import("mandatory_order.zig");
pub const monotone_witness = @import("monotone_witness.zig");
pub const fault_pause_transaction = @import("fault_pause_transaction.zig");
pub const sync_object_registry = @import("sync_object_registry.zig");
pub const run_journal = @import("run_journal.zig");
pub const execution_provenance = @import("execution_provenance.zig");
pub const execution_envelope = @import("execution_envelope.zig");
pub const coverage_board = @import("coverage_board.zig");
pub const durable_journal = @import("durable_journal.zig");
pub const evidence_replay = @import("evidence_replay.zig");
pub const test_census = @import("test_census.zig");
pub const guest_alias_contract = @import("guest_alias_contract.zig");
pub const storage_integrity = @import("storage_integrity.zig");
pub const execution_profile = @import("execution_profile.zig");
pub const run_budget = @import("run_budget.zig");
pub const run_manifest = @import("run_manifest.zig");
pub const xiso_preflight = @import("xiso_preflight.zig");
pub const kernel_service_readiness = @import("kernel_service_readiness.zig");
pub const import_integrity = @import("import_integrity.zig");
pub const pipeline_evidence = @import("pipeline_evidence.zig");
pub const acceptance_gates = @import("acceptance_gates.zig");
pub const timeout_fidelity = @import("timeout_fidelity.zig");
pub const signal_expectation = @import("signal_expectation.zig");
pub const wait_handshake_policy = @import("xenia_wait_handshake_policy");
pub const deadlock_predictor = @import("deadlock_predictor.zig");
pub const deferred_work = @import("deferred_work.zig");
pub const guest_exception_ledger = @import("guest_exception_ledger.zig");
pub const guest_status_ledger = @import("guest_status_ledger.zig");
pub const unknown_inventory = @import("unknown_inventory.zig");
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
pub const paired_observation = @import("paired_observation.zig");
pub const run_closure = @import("run_closure.zig");

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
    _ = xenia_gpu_causal_trace;
    _ = graphics_health_contract;
    _ = application_controller;
    _ = xenia_pm4_walk;
    _ = bringup_failure;
    _ = run_horizon;
    _ = claim_reconciliation;
    _ = interrupt_callback_transaction;
    _ = async_log;
    _ = run_integrity;
    _ = substantiation;
    _ = translation_economics;
    _ = guest_log_channels;
    _ = wait_graph;
    _ = wait_handshake_policy;
    _ = deadlock_predictor;
    _ = deferred_work;
    _ = guest_exception_ledger;
    _ = guest_status_ledger;
    _ = unknown_inventory;
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
    _ = mandatory_order;
    _ = monotone_witness;
    _ = fault_pause_transaction;
    _ = sync_object_registry;
    _ = run_journal;
    _ = execution_provenance;
    _ = execution_envelope;
    _ = coverage_board;
    _ = durable_journal;
    _ = evidence_replay;
    _ = test_census;
    _ = guest_alias_contract;
    _ = storage_integrity;
    _ = run_budget;
    _ = execution_profile;
    _ = run_manifest;
    _ = xiso_preflight;
    _ = kernel_service_readiness;
    _ = import_integrity;
    _ = acceptance_gates;
    _ = pipeline_evidence;
    _ = timeout_fidelity;
    _ = signal_expectation;
    _ = paired_observation;
    _ = run_closure;
}
