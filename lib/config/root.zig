//! Configuration.
//!
//! The schema — every key, its type, its default, and the registry that makes
//! a typo detectable — is `pkg/common/xenia/config-schema`. This library is the
//! runtime half: parsing a TOML file with `lib/processor/TOML_processor`,
//! binding it onto the schema, and layering per-title overrides.
//!
//! Precedence is fixed and stated in one place: **default, then global file,
//! then title override**. Most specific wins.
//!
//! The design rule throughout is that a configuration problem must never be
//! silent. An unknown key, a type mismatch, and an out-of-range value are all
//! reported with the key named, and the run continues on the default — because
//! a config error that stops the emulator is worse than one that is reported,
//! but one that is neither reported nor applied is the worst of the three.

pub const config = @import("config.zig");
pub const title_config = @import("title_config.zig");

pub const Config = config.Config;
pub const LoadResult = config.LoadResult;
pub const Diagnostic = config.Diagnostic;
pub const loadFromSlice = config.loadFromSlice;

pub const Overrides = title_config.Overrides;
pub const Resolution = title_config.Resolution;
pub const resolve = title_config.resolve;
pub const findOverrides = title_config.findOverrides;

// Re-exports do not root tests; without this block none of the above run.
test {
    _ = config;
    _ = title_config;
}
