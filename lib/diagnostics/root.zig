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
pub const diagnostic_text_accelerator = @import("diagnostic_text_accelerator.zig");
pub const semantic_fault_classifier = @import("semantic_fault_classifier.zig");
pub const control_transfer_classifier = @import("control_transfer_classifier.zig");
pub const x64_backend_diagnostics = @import("x64_backend_diagnostics.zig");
pub const xenia_pipeline_contracts = @import("xenia_pipeline_contracts.zig");
pub const xenia_pipeline = @import("xenia_pipeline.zig");
pub const spirv_cross_diagnostics = @import("spirv_cross_diagnostics.zig");
pub const opaque_lifetime_recovery = @import("opaque_lifetime_recovery.zig");
pub const launch_argument_accelerator = @import("launch_argument_accelerator.zig");
pub const startup_observer = @import("startup_observer.zig");
pub const logging_runtime = @import("logging_runtime.zig");
pub const runtime_output = @import("runtime_output.zig");
