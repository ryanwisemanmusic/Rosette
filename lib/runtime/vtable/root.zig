const std = @import("std");

pub const types = @import("types.zig");
pub const tracker = @import("tracker.zig");
pub const stack_registry = @import("stack_registry.zig");
pub const ownership = @import("ownership.zig");

pub const RecoveryMode = types.RecoveryMode;
pub const Policy = types.Policy;
pub const Provenance = types.Provenance;
pub const IdentityRejection = types.IdentityRejection;
pub const IdentityEvidence = types.IdentityEvidence;
pub const AllocationRecord = types.AllocationRecord;
pub const WriteDisposition = types.WriteDisposition;
pub const WriteResult = types.WriteResult;
pub const Recovery = types.Recovery;
pub const SuspiciousValueType = types.SuspiciousValueType;
pub const isAddressInMappedMemory = types.isAddressInMappedMemory;
pub const detectFunctionProloguePtr = types.detectFunctionProloguePtr;
pub const isItaniumVtableSymbol = types.isItaniumVtableSymbol;
pub const VtableOrigin = ownership.VtableOrigin;
pub const ObjectVtableState = ownership.ObjectVtableState;
pub const ConsistencyResult = ownership.ConsistencyResult;
pub const classifyOrigin = ownership.classifyOrigin;
pub const checkConsistency = ownership.checkConsistency;
pub const VtableTracker = tracker.VtableTracker;
pub const StackRegistry = stack_registry.StackRegistry;

test {
    std.testing.refAllDecls(types);
    std.testing.refAllDecls(tracker);
    std.testing.refAllDecls(stack_registry);
    std.testing.refAllDecls(ownership);
}
