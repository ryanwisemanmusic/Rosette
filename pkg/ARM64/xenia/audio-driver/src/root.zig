//! ARM64 host-side facts for the audio mixer and its callback.
//!
//! The console-side geometry — frame sizes, channel counts, XMA structure — is
//! `pkg/common/xenia/audio-contract` and does not change with the host. What
//! changes here is how the *host* must be configured to run a mixer without
//! introducing artefacts the guest never produced.
//!
//! ## Denormals are the route-specific hazard
//!
//! A reverb or filter tail decays toward zero and spends its last samples in
//! denormal range. On hardware that traps denormals to microcode, each one
//! costs orders of magnitude more than a normal multiply, and a decaying tail
//! turns into a burst of missed callback deadlines — audible as a stutter that
//! starts *after* a sound ends, which is a genuinely confusing signature. The
//! fix is a control-register bit, and which register and bit differ by route,
//! so this is exactly a route fact.
//!
//! ## What this package is not
//!
//! * It is not a driver. It opens no device and registers no callback;
//!   `lib/audio/` owns the host device and its lifetime.
//! * It holds no ring or buffer. A mix buffer is live state.
//! * It does not set the control register. Writing one is an effect, and the
//!   value is stated here so `lib/audio/` can apply it in one place.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_audio_backend = "coreaudio";

/// The host mixer works in 32-bit float.
pub const mix_sample_bytes: u32 = 4;

/// Width of the vector unit the mixer can rely on without a runtime check.
///
/// NEON is mandatory in AArch64, so a 128-bit mix needs no runtime
/// detection and no fallback path.
pub const mix_vector_bytes: u32 = 16;
pub const mix_samples_per_vector: u32 = mix_vector_bytes / mix_sample_bytes;
pub const mix_simd_extension = "neon";

/// The control register carrying the flush-to-zero controls, and the bits that
/// turn them on.
pub const denormal_control_register = "fpcr";
pub const denormal_control_bits: u32 = 0x1000000;

/// Stack alignment the ABI requires at a call boundary.
///
/// The audio callback runs on a stack Rosette hands it, and it shares that
/// stack with other guest callbacks. A misaligned frame does not fault
/// immediately; it faults later inside whichever routine first uses an aligned
/// vector store, which is nowhere near the callback that misaligned it.
pub const callback_stack_alignment: u32 = 16;

/// Whether a mix buffer of `bytes` can be processed as whole vectors.
pub fn isVectorSizedMix(bytes: u32) bool {
    return bytes != 0 and bytes % mix_vector_bytes == 0;
}

/// Whether a stack pointer is acceptable at a callback entry.
pub fn isCallbackStackAligned(stack_pointer: u64) bool {
    return stack_pointer % callback_stack_alignment == 0;
}

test "package identity is the ARM64 audio route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("neon", mix_simd_extension);
    try std.testing.expectEqualStrings("fpcr", denormal_control_register);
}

test "the denormal controls are a non-empty bit set in the route's register" {
    // Zero here would mean "no flush-to-zero available", which is not true on
    // either route and would leave the decaying-tail stall in place.
    try std.testing.expect(denormal_control_bits != 0);
    try std.testing.expectEqual(@as(u32, 0x1000000), denormal_control_bits);
}

test "the vector width divides the console frame evenly" {
    // 6144 bytes per host frame, from pkg/common/xenia/audio-contract. If the
    // vector width did not divide it, the mixer would need a scalar tail on
    // every frame and the tail is where off-by-one bugs live.
    try std.testing.expectEqual(@as(u32, 4), mix_samples_per_vector);
    try std.testing.expect(isVectorSizedMix(6144));
    try std.testing.expectEqual(@as(u32, 0), 6144 % mix_vector_bytes);
}

test "a partial vector is not a vector sized mix" {
    try std.testing.expect(!isVectorSizedMix(0));
    try std.testing.expect(!isVectorSizedMix(4));
    try std.testing.expect(!isVectorSizedMix(6145));
    try std.testing.expect(isVectorSizedMix(mix_vector_bytes));
}

test "callback stacks are sixteen byte aligned" {
    // Shared with the other guest callbacks, so an unaligned entry here
    // surfaces as a fault inside an unrelated routine later.
    try std.testing.expect(isCallbackStackAligned(0x4_0000));
    try std.testing.expect(isCallbackStackAligned(0x4_0010));
    try std.testing.expect(!isCallbackStackAligned(0x4_0008));
    try std.testing.expect(!isCallbackStackAligned(0x4_0001));
}
