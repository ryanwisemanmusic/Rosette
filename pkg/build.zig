//! Package-owned test registration, imported by the repository build coordinator.
//! Paths passed to `b.path` remain relative to the master build root.
const std = @import("std");

pub fn register(b: *std.Build, ctx: anytype) void {
    const check_step = ctx.check_step;
    const optimize = ctx.optimize;
    const target = ctx.target;
    const rosette_translation_cache_contract_mod = ctx.rosette_translation_cache_contract_mod;
    const host_x86_guest_endian_mod = ctx.host_x86_guest_endian_mod;
    const host_arm64_guest_endian_mod = ctx.host_arm64_guest_endian_mod;
    const host_ppc64_guest_endian_mod = ctx.host_ppc64_guest_endian_mod;
    const endianness_x86_mod = ctx.endianness_x86_mod;
    const endianness_arm64_mod = ctx.endianness_arm64_mod;
    const endianness_ppc_mod = ctx.endianness_ppc_mod;
    const sha_x86_mod = ctx.sha_x86_mod;
    const sha_arm64_mod = ctx.sha_arm64_mod;
    const sha_ppc_mod = ctx.sha_ppc_mod;
    const dxbc_x86_mod = ctx.dxbc_x86_mod;
    const dxbc_arm64_mod = ctx.dxbc_arm64_mod;
    const dxbc_ppc_mod = ctx.dxbc_ppc_mod;
    const half_x86_mod = ctx.half_x86_mod;
    const half_arm64_mod = ctx.half_arm64_mod;
    const half_ppc_mod = ctx.half_ppc_mod;

    // The route packages under `pkg/` ship inside the processor, so their
    // own tests belong in the same gate as everything else that does.
    // Each package carries a `verify.sh`, but a check that only runs when
    // someone remembers to run it is not a check — a drifted package
    // reached the built binary and the suite stayed green.
    //
    // Both routes are tested regardless of which one this build selects.
    // The unselected one is the companion that a later ARM64 or x86 host
    // will link, and letting it rot until that host exists is how the
    // "preflight contract" packages stop matching the route they mirror.
    // Not a route package — one file, no mirror — but it ships inside the
    // processor and its tests belong in the same gate as everything else
    // that does.
    const common_package_roots = [_][]const u8{
        "pkg/common/abi/receiver-classification/src/root.zig",
        "pkg/common/xenos/register-map/src/root.zig",
        "pkg/common/abi/near-null-shape/src/root.zig",
        "pkg/common/console/log-phrase-map/src/root.zig",
        "pkg/common/abi/host-contract-catalogue/src/root.zig",
        "pkg/common/text/phrase-filter/src/root.zig",
        "pkg/common/console/ready-plan/src/root.zig",
        // Console-hardware and kernel-ABI contracts. Route-independent for
        // the same reason register-map is: they describe the Xbox 360 and
        // its kernel, not the host Rosette was compiled for.
        "pkg/common/console/audio-contract/src/root.zig",
        "pkg/common/console/input-contract/src/root.zig",
        "pkg/common/console/user-contract/src/root.zig",
        "pkg/common/console/config-schema/src/root.zig",
        "pkg/common/console/gpu-bringup-contract/src/root.zig",
        "pkg/common/console/gpu-observation-contract/src/root.zig",
        "pkg/common/console/shader-contract/src/root.zig",
        "pkg/common/console/render-target-contract/src/root.zig",
        "pkg/common/console/texture-contract/src/root.zig",
        "pkg/common/console/io-completion-contract/src/root.zig",
        "pkg/common/console/timer-contract/src/root.zig",
        "pkg/common/console/ob-contract/src/root.zig",
        "pkg/common/console/mount-contract/src/root.zig",
        "pkg/common/console/kernel-object-contract/src/root.zig",
        // Facts transcribed from Xenia's own tables and headers. They
        // describe the console and its kernel, so they are route
        // independent like the rest of this list.
        "pkg/common/console/kernel-export-map/src/root.zig",
        "pkg/common/console/kernel-shim-map/src/root.zig",
        "pkg/common/console/vd-ring-contract/src/root.zig",
        "pkg/common/console/vd-swap-contract/src/root.zig",
        "pkg/common/console/provisioning-contract/src/root.zig",
        "pkg/common/console/claim-reconciliation-contract/src/root.zig",
        "pkg/common/diagnostics/async-log-contract/src/root.zig",
        "pkg/common/abi/translation-economics-contract/src/root.zig",
        "pkg/common/rosette/translation-cache-contract/src/root.zig",
        "pkg/common/console/draw-dispatch-contract/src/root.zig",
        "pkg/common/console/wait-graph-contract/src/root.zig",
        "pkg/common/console/wait-handshake-policy/src/root.zig",
        "pkg/common/console/pm4-contract/src/root.zig",
        "pkg/common/console/xex-format/src/root.zig",
        "pkg/common/console/notification-contract/src/root.zig",
        "pkg/common/console/log-ring-contract/src/root.zig",
        "pkg/common/console/xthread-contract/src/root.zig",
        "pkg/common/console/vfs-device-contract/src/root.zig",
        "pkg/common/console/launch-assist-contract/src/root.zig",
        "pkg/common/rosette/ownership-contract/src/root.zig",
        "pkg/common/rosette/source-architecture-contract/src/root.zig",
        "pkg/common/console/rosette-script-contract/src/root.zig",
    };
    inline for (common_package_roots) |package_root| {
        const package_mod = b.createModule(.{
            .root_source_file = b.path(package_root),
            .target = target,
            .optimize = optimize,
        });
        // Two of these import the shared rejection filter. Supplying it to
        // every common package is harmless for the rest and keeps this loop
        // from needing a per-package dependency table that would drift.
        // A fresh module is used rather than `phrase_filter_mod`, which is
        // declared in the build-artifact scope above and not visible here.
        package_mod.addImport("phrase_filter", b.createModule(.{
            .root_source_file = b.path("pkg/common/text/phrase-filter/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }));
        package_mod.addImport("rosette_translation_cache_contract", rosette_translation_cache_contract_mod);
        const package_test = b.addTest(.{ .root_module = package_mod });
        check_step.dependOn(&b.addRunArtifact(package_test).step);
    }

    const route_package_roots = [_][]const u8{
        "pkg/x86/console/graphics-contract/src/root.zig",
        "pkg/x86/console/graphics/surface-path-contract/src/root.zig",
        "pkg/x86/console/bridge/abi-bridge/src/root.zig",
        // This package's tests live beside the evidence table rather than
        // in a `root.zig`; `main.zig` is its executable half.
        "pkg/x86/console/diagnostics/startup-evidence/src/evidence.zig",
        "pkg/x86/console/runtime/codegen-activation/src/root.zig",
        "pkg/x86/console/runtime/launch-phase-map/src/root.zig",
        "pkg/x86/console/runtime/primitive-contract/src/root.zig",
        "pkg/x86/console/runtime/guest-bridge/src/root.zig",
        "pkg/x86/console/runtime/shader-storage-contract/src/root.zig",
        "pkg/x86/console/runtime/wait-contract/src/root.zig",
        "pkg/x86/console/runtime/translation-progress/src/root.zig",
        "pkg/x86/console/memory/heap-range/src/root.zig",
        "pkg/x86/console/audio-driver/src/root.zig",
        "pkg/x86/console/input-driver/src/root.zig",
        "pkg/x86/console/simd-shim-map/src/root.zig",
        "pkg/ARM64/console/graphics-contract/src/root.zig",
        "pkg/ARM64/console/graphics/surface-path-contract/src/root.zig",
        "pkg/ARM64/console/bridge/abi-bridge/src/root.zig",
        // Same split as the x86 copy: the tests live beside the evidence
        // table, and `main.zig` is the executable half.
        "pkg/ARM64/console/diagnostics/startup-evidence/src/evidence.zig",
        "pkg/ARM64/console/runtime/codegen-activation/src/root.zig",
        "pkg/ARM64/console/runtime/guest-bridge/src/root.zig",
        "pkg/ARM64/console/runtime/launch-phase-map/src/root.zig",
        "pkg/ARM64/console/runtime/primitive-contract/src/root.zig",
        "pkg/ARM64/console/runtime/shader-storage-contract/src/root.zig",
        "pkg/ARM64/console/runtime/wait-contract/src/root.zig",
        "pkg/ARM64/console/runtime/translation-progress/src/root.zig",
        "pkg/ARM64/console/memory/heap-range/src/root.zig",
        "pkg/ARM64/console/audio-driver/src/root.zig",
        "pkg/ARM64/console/input-driver/src/root.zig",
        "pkg/ARM64/console/simd-shim-map/src/root.zig",
        "pkg/x86/console/guest-endian/src/root.zig",
        "pkg/ARM64/console/guest-endian/src/root.zig",
        "pkg/PPC/console/guest-endian/src/root.zig",
        "pkg/PPC/console/runtime/instruction-routing/src/root.zig",
        "pkg/x86/third_party/endianness/src/root.zig",
        "pkg/ARM64/third_party/endianness/src/root.zig",
        "pkg/PPC/third_party/endianness/src/root.zig",
        "pkg/x86/third_party/crypto/sha/src/root.zig",
        "pkg/ARM64/third_party/crypto/sha/src/root.zig",
        "pkg/PPC/third_party/crypto/sha/src/root.zig",
        "pkg/x86/third_party/dxbc/src/root.zig",
        "pkg/ARM64/third_party/dxbc/src/root.zig",
        "pkg/PPC/third_party/dxbc/src/root.zig",
        "pkg/x86/third_party/half/src/root.zig",
        "pkg/ARM64/third_party/half/src/root.zig",
        "pkg/PPC/third_party/half/src/root.zig",
    };
    inline for (route_package_roots) |package_root| {
        const package_mod = b.createModule(.{
            .root_source_file = b.path(package_root),
            .target = target,
            .optimize = optimize,
        });
        const package_test = b.addTest(.{ .root_module = package_mod });
        check_step.dependOn(&b.addRunArtifact(package_test).step);
    }

    const guest_endian_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("pkg/common/equivalence/guest-endian/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    guest_endian_equivalence_mod.addImport("x86_guest_endian", host_x86_guest_endian_mod);
    guest_endian_equivalence_mod.addImport("arm64_guest_endian", host_arm64_guest_endian_mod);
    guest_endian_equivalence_mod.addImport("ppc_guest_endian", host_ppc64_guest_endian_mod);
    const guest_endian_equivalence_test = b.addTest(.{ .root_module = guest_endian_equivalence_mod });
    check_step.dependOn(&b.addRunArtifact(guest_endian_equivalence_test).step);

    const endianness_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("pkg/common/equivalence/endianness/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    endianness_equivalence_mod.addImport("x86_endianness", endianness_x86_mod);
    endianness_equivalence_mod.addImport("arm64_endianness", endianness_arm64_mod);
    endianness_equivalence_mod.addImport("ppc_endianness", endianness_ppc_mod);
    const endianness_equivalence_test = b.addTest(.{ .root_module = endianness_equivalence_mod });
    check_step.dependOn(&b.addRunArtifact(endianness_equivalence_test).step);

    const sha_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("pkg/common/equivalence/sha/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    sha_equivalence_mod.addImport("x86_sha", sha_x86_mod);
    sha_equivalence_mod.addImport("arm64_sha", sha_arm64_mod);
    sha_equivalence_mod.addImport("ppc_sha", sha_ppc_mod);
    const sha_equivalence_test = b.addTest(.{ .root_module = sha_equivalence_mod });
    check_step.dependOn(&b.addRunArtifact(sha_equivalence_test).step);

    const dxbc_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("pkg/common/equivalence/dxbc/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    dxbc_equivalence_mod.addImport("x86_dxbc", dxbc_x86_mod);
    dxbc_equivalence_mod.addImport("arm64_dxbc", dxbc_arm64_mod);
    dxbc_equivalence_mod.addImport("ppc_dxbc", dxbc_ppc_mod);
    const dxbc_equivalence_test = b.addTest(.{ .root_module = dxbc_equivalence_mod });
    check_step.dependOn(&b.addRunArtifact(dxbc_equivalence_test).step);

    const half_equivalence_mod = b.createModule(.{
        .root_source_file = b.path("pkg/common/equivalence/half/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    half_equivalence_mod.addImport("x86_half", half_x86_mod);
    half_equivalence_mod.addImport("arm64_half", half_arm64_mod);
    half_equivalence_mod.addImport("ppc_half", half_ppc_mod);
    const half_equivalence_test = b.addTest(.{ .root_module = half_equivalence_mod });
    check_step.dependOn(&b.addRunArtifact(half_equivalence_test).step);
}
