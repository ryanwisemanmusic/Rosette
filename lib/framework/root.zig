//! Public runtime module for the Rosette application framework.

pub const contract = @import("application_framework_contract");
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
