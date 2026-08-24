//! Shaders.
//!
//! Microcode structure, a small SSA IR, two backends, a cache, and a software
//! reference executor.
//!
//! ## The shape of the subsystem
//!
//! Microcode goes to one IR (`microcode_to_ssa`), and the IR goes to MSL
//! (`ssa_to_msl`), SPIR-V (`ssa_to_spirv`), or a software interpreter
//! (`shader_interpreter`). The single IR is the load-bearing decision: emitting
//! two host languages directly from microcode means every semantic question —
//! modifier order, what a dot product writes, what a write mask preserves — is
//! answered twice, and the two answers drift. When they drift a title renders
//! correctly on one backend and not the other, and the difference gets
//! attributed to the host driver.
//!
//! The interpreter exists for the same reason from the other direction. "The
//! image is wrong" is unattributable with two implementations and attributable
//! with three: if the interpreter agrees with one backend and not the other,
//! the disagreeing backend is wrong.
//!
//! `xenos_microcode` checks structure before anything trusts an instruction,
//! because structural errors are detectable and semantic ones mostly are not.
//!
//! Limits are `pkg/common/xenia/shader-contract`.

pub const xenos_microcode = @import("xenos_microcode.zig");
pub const microcode_to_ssa = @import("microcode_to_ssa.zig");
pub const ssa_to_msl = @import("ssa_to_msl.zig");
pub const ssa_to_spirv = @import("ssa_to_spirv.zig");
pub const shader_cache = @import("shader_cache.zig");
pub const shader_interpreter = @import("shader_interpreter.zig");

pub const Program = microcode_to_ssa.Program;
pub const Instruction = microcode_to_ssa.Instruction;
pub const Source = microcode_to_ssa.Source;
pub const Op = microcode_to_ssa.Op;
pub const Cache = shader_cache.Cache;
pub const Invocation = shader_interpreter.Invocation;

// Re-exports do not root tests; without this block none of the above run.
test {
    _ = xenos_microcode;
    _ = microcode_to_ssa;
    _ = ssa_to_msl;
    _ = ssa_to_spirv;
    _ = shader_cache;
    _ = shader_interpreter;
}
