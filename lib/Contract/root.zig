const std = @import("std");

pub const contract = @import("contract.zig");
pub const runtime = @import("runtime.zig");
pub const verify = @import("verify.zig");

pub const ContractKind = contract.ContractKind;
pub const ResolutionStrategy = contract.ResolutionStrategy;
pub const MatchPattern = contract.MatchPattern;
pub const Parameter = contract.Parameter;
pub const ReturnPolicy = contract.ReturnPolicy;
pub const Contract = contract.Contract;

pub const ContractRegistry = runtime.ContractRegistry;
pub const PosixContracts = runtime.PosixContracts;
pub const PosixExtendedContracts = runtime.PosixExtendedContracts;
pub const TimeContracts = runtime.TimeContracts;
pub const FileIoContracts = runtime.FileIoContracts;
pub const StdioContracts = runtime.StdioContracts;
pub const MiscContracts = runtime.MiscContracts;
pub const CxxContracts = runtime.CxxContracts;
pub const ObjcContracts = runtime.ObjcContracts;

pub const dispatchFromAllFamilies = runtime.dispatchFromAllFamilies;
pub const resolveFromAllFamilies = runtime.resolveFromAllFamilies;

pub const verifyDispatch = verify.verifyDispatch;
pub const resolveExpected = verify.resolveExpected;

test "Contract contract.zig tests" {
    _ = @import("contract.zig");
}

test "Contract runtime.zig tests" {
    _ = @import("runtime.zig");
}

test "Contract verify.zig tests" {
    _ = @import("verify.zig");
}
