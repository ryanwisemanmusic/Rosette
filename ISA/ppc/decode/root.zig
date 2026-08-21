//! Rosette's PowerPC decode module.
//!
//! The Xbox 360's Xenon core is a 64-bit PowerPC with AltiVec and the VMX128
//! extension. This module owns instruction identity and field extraction only:
//! what an encoding *is*. What it *does* lives in lib/runtime/ppc, and the
//! architectural contract for each instruction lives in ISA/ppc/<GROUP>/.
//!
//!   fields  - form-by-form field extraction, both bit numberings reconciled
//!   opcode  - the Op enum and per-instruction metadata (generated)
//!   table   - the primary/extended decode tree (generated)
//!   decoder - the entry points: decodeWord, decodeBytes, decodeSlice, decodeBlock

const std = @import("std");

pub const fields = @import("fields.zig");
pub const opcode = @import("opcode.zig");
pub const table = @import("table.zig");
pub const decoder = @import("decoder.zig");

pub const Op = opcode.Op;
pub const Form = opcode.Form;
pub const Group = opcode.Group;
pub const Info = opcode.Info;
pub const Instruction = decoder.Instruction;

pub const decodeWord = decoder.decodeWord;
pub const decodeBytes = decoder.decodeBytes;
pub const decodeSlice = decoder.decodeSlice;
pub const decodeBlock = decoder.decodeBlock;
pub const decodeOp = table.decodeOp;

test {
    std.testing.refAllDecls(@This());
    _ = fields;
    _ = opcode;
    _ = table;
    _ = decoder;
}
