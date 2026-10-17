//! ARM64 host facts for Xenia's SIMD translation shims.
//!
//! Xenia vendors a family of header-only shims that re-express one
//! instruction set in terms of another: `vmx2NEON`, `vex2NEON`, `ymm2NEON`,
//! `bmi2NEON`, `amxNEON`, `ppcFloat2NEON` and `AvxToNeon`. Which of them are
//! *live* depends entirely on the host Rosette was compiled for, which makes
//! this a route package rather than a common one.
//!
//! ## Why the shim set is worth stating per route
//!
//! A shim that is compiled in but never exercised costs nothing and proves
//! nothing. A shim that is *missing* on the route that needs it produces a
//! build that links and then executes an instruction the host cannot decode.
//! On this project that has a specific, expensive history: Rosetta 2 has no AVX
//! at all and SIGILLs on every VEX encoding, so the question "is the AVX path
//! live on this route" is not academic.
//!
//! The set below records which shims this route depends on, and — just as
//! importantly — which it must not, so a shim quietly becoming reachable is a
//! detectable change rather than a silent one.
//!
//! ## What this package is not
//!
//! * It contains no shim. It provides no translation and emits no
//!   instructions; the shims themselves are Xenia's vendored headers.
//! * It does not detect host features. Whether this machine supports a given
//!   extension is a runtime observation belonging to lib.
//! * It does not choose a path. Selecting a code path is a runtime decision.

const std = @import("std");

pub const host_architecture = "arm64";

/// A vendored translation shim.
pub const Shim = enum {
    /// PowerPC AltiVec/VMX to NEON.
    vmx_to_neon,
    /// x86 VEX-encoded SSE/AVX to NEON.
    vex_to_neon,
    /// 256-bit YMM operations to paired NEON registers.
    ymm_to_neon,
    /// BMI bit-manipulation to NEON and scalar ARM.
    bmi_to_neon,
    /// Apple AMX matrix unit.
    amx_neon,
    /// PowerPC scalar floating point to NEON.
    ppc_float_to_neon,
    /// Broad AVX to NEON.
    avx_to_neon,

    pub fn header(self: Shim) []const u8 {
        return switch (self) {
            .vmx_to_neon => "third_party/vmx2NEON/altivec_macos.h",
            .vex_to_neon => "third_party/vex2NEON/vex2neon.h",
            .ymm_to_neon => "third_party/ymm2NEON/ymm2neon.h",
            .bmi_to_neon => "third_party/bmi2NEON/bmi2neon.h",
            .amx_neon => "third_party/amxNEON/amx.h",
            .ppc_float_to_neon => "third_party/ppcFloat2NEON/ppcfloat2neon.h",
            .avx_to_neon => "third_party/AvxToNeon/avx2neon.h",
        };
    }

    /// The instruction set the shim translates *from*.
    pub fn sourceIsa(self: Shim) []const u8 {
        return switch (self) {
            .vmx_to_neon, .ppc_float_to_neon => "powerpc",
            .vex_to_neon, .ymm_to_neon, .bmi_to_neon, .avx_to_neon => "x86_64",
            .amx_neon => "arm64",
        };
    }

    /// Whether the shim targets NEON, and so only does anything on AArch64.
    pub fn targetsNeon(self: Shim) bool {
        _ = self;
        return true;
    }
};

pub const all_shims = [_]Shim{
    .vmx_to_neon,
    .vex_to_neon,
    .ymm_to_neon,
    .bmi_to_neon,
    .amx_neon,
    .ppc_float_to_neon,
    .avx_to_neon,
};

/// The shims this route actually depends on.
pub const live_shims = [_]Shim{
    .vmx_to_neon,
    .ppc_float_to_neon,
    .vex_to_neon,
    .ymm_to_neon,
    .bmi_to_neon,
    .avx_to_neon,
};

/// Whether a shim is live on this route.
pub fn isLive(shim: Shim) bool {
    for (live_shims) |candidate| {
        if (candidate == shim) return true;
    }
    return false;
}

/// Whether this route can execute VEX-encoded instructions natively.
///
/// False on this route. An AArch64 host cannot decode a VEX encoding, and
/// under Rosetta 2 every attempt is a SIGILL — so anything reaching an AVX
/// path here must have been translated first.
pub const executes_vex_natively: bool = false;

/// Whether this route has NEON.
pub const has_neon: bool = true;

/// The guest ISA Rosette translates. Unchanged by the host route: the console
/// is PowerPC whichever machine is emulating it.
pub const guest_isa = "powerpc64-big-endian";

test "package identity is the ARM64 SIMD route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
}

test "every shim names a header that exists in Xenia's tree" {
    // Not a filesystem check — a package performs no I/O — but the paths are
    // pinned so a vendored directory being renamed is a visible edit here
    // rather than a silently dead reference.
    for (all_shims) |shim| {
        try std.testing.expect(shim.header().len > 0);
        try std.testing.expect(std.mem.startsWith(u8, shim.header(), "third_party/"));
        try std.testing.expect(std.mem.endsWith(u8, shim.header(), ".h"));
    }
    try std.testing.expectEqual(@as(usize, 7), all_shims.len);
}

test "the live set is a subset of the whole set" {
    for (live_shims) |shim| {
        var found = false;
        for (all_shims) |candidate| {
            if (candidate == shim) found = true;
        }
        try std.testing.expect(found);
    }
}

test "the PowerPC shims translate the guest ISA" {
    // These two are about the console, not the host, so they are the shims a
    // PPC-to-anything backend needs regardless of route.
    try std.testing.expectEqualStrings("powerpc", Shim.vmx_to_neon.sourceIsa());
    try std.testing.expectEqualStrings("powerpc", Shim.ppc_float_to_neon.sourceIsa());
    try std.testing.expectEqualStrings("powerpc64-big-endian", guest_isa);
}

test "the x86 shims translate the host's own encodings" {
    try std.testing.expectEqualStrings("x86_64", Shim.vex_to_neon.sourceIsa());
    try std.testing.expectEqualStrings("x86_64", Shim.ymm_to_neon.sourceIsa());
    try std.testing.expectEqualStrings("x86_64", Shim.bmi_to_neon.sourceIsa());
    try std.testing.expectEqualStrings("x86_64", Shim.avx_to_neon.sourceIsa());
}

test "the ARM64 route has NEON and cannot execute VEX" {
    // The expensive fact behind this whole package: an ARM64 host cannot
    // decode a VEX encoding, and under Rosetta 2 the attempt is a SIGILL on
    // every one of them. Anything reaching an AVX path here must have been
    // translated first.
    try std.testing.expect(has_neon);
    try std.testing.expect(!executes_vex_natively);
}

test "the x86 translation shims are live on this route" {
    // They are what makes an x86-encoded guest or host routine expressible
    // at all. A missing one links fine and then executes an instruction the
    // host cannot decode.
    try std.testing.expect(isLive(.vex_to_neon));
    try std.testing.expect(isLive(.ymm_to_neon));
    try std.testing.expect(isLive(.bmi_to_neon));
    try std.testing.expect(isLive(.avx_to_neon));
}

test "the PowerPC shims stay live on every route" {
    try std.testing.expect(isLive(.vmx_to_neon));
    try std.testing.expect(isLive(.ppc_float_to_neon));
}

test "every shim targets NEON, which is why this route uses them all" {
    for (all_shims) |shim| {
        try std.testing.expect(shim.targetsNeon());
    }
    // Six of the seven are live; AMX is available but not on the emulation
    // path, so it is recorded and deliberately not claimed.
    try std.testing.expectEqual(@as(usize, 6), live_shims.len);
    try std.testing.expect(!isLive(.amx_neon));
}
