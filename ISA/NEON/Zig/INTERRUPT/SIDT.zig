pub const family = "INTERRUPT";
pub const path = "INTERRUPT/SIDT.inc";
pub const source = @embedFile("../../INTERRUPT/SIDT.inc");
pub const x86_path = "INTERRUPT/SIDT.inc";
pub const target_isa = "arm64_neon";
