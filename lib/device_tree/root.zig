//! Rosette-native, versioned hardware description.
//!
//! Linux device trees inspired the separation between hardware facts and the
//! code consuming them. This is not an FDT/DTB implementation: desktop host
//! APIs already perform enumeration, and Rosette needs typed negotiated facts,
//! provenance, and policy validation rather than firmware boot discovery.
//!
//! The part descriptions under `cpu/` and `gpu/` carry the other half: not what
//! the hardware *is*, but what it *fixes*. A constraint there is something the
//! runtime can ask before acting — is this protection enforceable at the guest's
//! page size, do these two addresses name the same physical storage, is a fault
//! at this address a mapping defect or a null dereference — and every one of
//! them was previously learned by hitting it instead.

pub const schema = @import("schema.zig");
pub const format = @import("format.zig");
pub const profile = @import("profile.zig");
pub const constraint = @import("constraint.zig");

/// Parts, one directory each. A fact about the CPU and a fact about the GPU are
/// different kinds of knowledge with different consumers, and keeping them in
/// one flat namespace is what makes a hardware description degenerate into a
/// bag of constants.
pub const cpu = struct {
    pub const xenon = @import("cpu/xenon.zig");
};

pub const gpu = struct {
    pub const xenos = @import("gpu/xenos.zig");
};

pub const Tree = schema.Tree;
pub const Value = schema.Value;
pub const Source = schema.Source;
pub const Mutability = schema.Mutability;
pub const NodeKind = schema.NodeKind;
pub const Status = schema.Status;

test {
    _ = schema;
    _ = format;
    _ = profile;
    _ = constraint;
    _ = cpu.xenon;
    _ = gpu.xenos;
}
