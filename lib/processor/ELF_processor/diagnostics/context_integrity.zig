//! Public facade for PE guest register-file comparison and recovery.

const register_file = @import("context_integrity/register_file.zig");

pub const gpr_names = register_file.gpr_names;
pub const Difference = register_file.Difference;
pub const compare = register_file.compare;
pub const restoreArchitecturalState = register_file.restoreArchitecturalState;

test {
    _ = register_file;
}
