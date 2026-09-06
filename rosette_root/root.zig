//! Rosette framework root for build-time route selection.
//!
//! Runtime libraries import this root when they need a fixed framework fact.
//! It must not import Mach-O state or Xenia: the direction is deliberately
//! one-way, from package facts into runtime observers.

pub const gpu = @import("rosette_gpu_root");
pub const gpu_profile = gpu.profile;

comptime {
    if (gpu_profile.xe_swap_signature != 0x5357_4150) {
        @compileError("Rosette root has a drifted XE_SWAP signature");
    }
}

test {
    _ = gpu;
}
