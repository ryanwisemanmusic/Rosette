//! Public runtime module for the Rosette application framework.

pub const contract = @import("application_framework_contract");
pub const xenia_launch_assist = @import("xenia_launch_assist.zig");
pub const xenia_host_gpu_callback_contract = @import("xenia_host_gpu_callback_contract");
pub const xenia_host_gpu_callback = @import("xenia_host_gpu_callback.zig");
pub const application_framework = @import("application_framework.zig");
pub const Framework = application_framework.Framework;
pub const default_framework = &application_framework.default_framework;
pub const defaultHandle = application_framework.defaultHandle;
pub const activateDefault = application_framework.activateDefault;
pub const deactivateDefault = application_framework.deactivateDefault;
pub const hashName = application_framework.hashName;

test {
    _ = application_framework;
}
