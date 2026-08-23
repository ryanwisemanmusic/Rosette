//! Link-set audit: implicit symbol-resolution defects in a completed build.
//!
//! A compiler diagnoses one translation unit and a linker diagnoses hard
//! errors. Neither reports the resolutions that are merely *arbitrary* — a
//! symbol defined strongly in two places, an entry point defined twice, a
//! definition chosen by archive member order. Those build cleanly and then
//! decide behaviour at runtime, which is exactly the class of failure Rosette
//! ends up hosting.
//!
//! The audit runs over the finished link set, because that is the only point
//! where the question is answerable: an object file on its own cannot know
//! what else defines its symbols.

const std = @import("std");

pub const types = @import("types.zig");
pub const audit = @import("audit.zig");
pub const object = @import("object.zig");
pub const scan = @import("scan.zig");

pub const Linkage = types.Linkage;
pub const FindingKind = types.FindingKind;
pub const Severity = types.Severity;
pub const Finding = types.Finding;
pub const Audit = audit.Audit;
pub const Scanner = scan.Scanner;

test {
    _ = types;
    _ = audit;
    _ = object;
    _ = scan;
}
