//! The Xenia startup compile plan.
//!
//! Deliberately specific. Every entry names a real precondition of the Halo 3
//! startup contract, and the vocabulary has no meaning for another guest. A
//! generic version of this written before a second guest exists would be an
//! abstraction fitted to one example.
//!
//! Symbols are matched by prefix plus a distinctive fragment rather than by
//! full mangled name. A full name encodes the whole signature, so adding a
//! parameter to a Xenia function would turn a real check into a spurious
//! failure; the fragment carries the Itanium length prefix (`5SetupE`,
//! `23InitializeShaderStorage`) and is stable against that.

const std = @import("std");
const plan = @import("plan.zig");
const xenia = @import("xenia.zig");
const cache = @import("cache.zig");
const ready_package = @import("package.zig");

pub const symbol_prefix = "__ZN2xe";

/// Changes to the static contract invalidate the plan cache.  The fingerprint
/// is derived from the actual declarations rather than maintained as a second
/// hand-written version number, so adding/reordering a target cannot silently
/// reuse an old reference bitmap.
pub fn fingerprint() u64 {
    var result = std.hash.Wyhash.hash(0, symbol_prefix);
    for (contract_units) |unit| {
        result = std.hash.Wyhash.hash(result, unit.fragment);
        result = std.hash.Wyhash.hash(result, unit.purpose);
        var stage = @intFromEnum(unit.stage);
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&stage));
        var reachability_required = unit.reachability_required;
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&reachability_required));
    }
    for (symbol_units) |unit| {
        result = std.hash.Wyhash.hash(result, unit.fragment);
        result = std.hash.Wyhash.hash(result, unit.purpose);
        var required = unit.required;
        result = std.hash.Wyhash.hash(result, std.mem.asBytes(&required));
    }
    return result;
}

/// Build the package manifest that may be vendored or reused by a later
/// Rosetta run. The package carries the static-plan bitmap and contract
/// identity, not generated code or live runtime state.
pub fn packageManifest(snapshot: cache.Snapshot) ready_package.Manifest {
    var manifest = ready_package.Manifest.init(
        .xenia_halo3_startup,
        .x86_64,
        .little,
        64,
        1,
        fingerprint(),
        snapshot.image_fingerprint,
    );
    manifest.static_plan_target_fingerprint = snapshot.target_fingerprint;
    manifest.static_plan_target_count = snapshot.target_count;
    manifest.static_plan_referenced_mask = snapshot.referenced_mask;
    manifest.static_plan_scanned_bytes = snapshot.scanned_bytes;
    manifest.static_plan_direct_call_sites = snapshot.direct_call_sites;
    _ = manifest.addArtifact(.{
        .kind = .ready_contract,
        .architecture = .any,
        .flags = ready_package.ArtifactFlags.static_evidence | ready_package.ArtifactFlags.portable,
        .size = @intCast(xenia.contract().stages.len),
        .content_fingerprint = fingerprint(),
    });
    const static_plan_bytes: [7]u64 = .{
        snapshot.image_fingerprint,
        snapshot.contract_fingerprint,
        snapshot.target_fingerprint,
        snapshot.target_count,
        snapshot.referenced_mask,
        snapshot.scanned_bytes,
        snapshot.direct_call_sites,
    };
    _ = manifest.addArtifact(.{
        .kind = .static_plan,
        .architecture = .x86_64,
        .flags = ready_package.ArtifactFlags.static_evidence,
        .size = cache.serialized_size,
        .content_fingerprint = std.hash.Wyhash.hash(0, std.mem.asBytes(&static_plan_bytes)),
        .dependency_fingerprint = snapshot.target_fingerprint,
    });
    return manifest;
}

/// A function whose absence makes some part of startup impossible.
pub const SymbolUnit = struct {
    fragment: []const u8,
    purpose: []const u8,
    required: bool = true,
};

/// A contract stage tied to the code that must run for it to be reported.
pub const ContractUnit = struct {
    stage: xenia.Stage,
    fragment: []const u8,
    purpose: []const u8,
    /// Whether absence of any reference to the implementation halts the plan.
    ///
    /// Advisory by default, and that default is a statement about the analysis
    /// rather than about Xenia. The reference scan finds direct `call rel32`
    /// sites; Xenia reaches a great deal of its startup through virtual
    /// dispatch and `std::function`, whose targets live in tables the scan does
    /// not cover. A missing reference is therefore strong evidence and not
    /// proof, and halting a run on it would be failing the build over a limit
    /// of the gate's own vision.
    ///
    /// The presence half of the same stage is a separate, required unit, so a
    /// genuinely missing implementation still halts.
    reachability_required: bool = false,
};

/// The code without which the corresponding startup stage cannot occur.
///
/// The ordering mirrors the contract so the emitted plan reads in the order
/// the run will need these, the way a build log reads in dependency order.
pub const contract_units = [_]ContractUnit{
    .{ .stage = .emulator_setup_started, .fragment = "8Emulator5SetupE", .purpose = "Emulator::Setup must exist to begin bring-up" },
    .{ .stage = .memory_ready, .fragment = "6Memory10InitializeE", .purpose = "guest memory initialization" },
    .{ .stage = .processor_ready, .fragment = "3cpu9Processor5SetupE", .purpose = "CPU frontend and backend bring-up" },
    .{ .stage = .kernel_globals_started, .fragment = "11KernelState28InitializeKernelGuestGlobalsE", .purpose = "kernel guest globals" },
    .{ .stage = .graphics_setup_started, .fragment = "14GraphicsSystem5SetupE", .purpose = "GraphicsSystem::Setup" },
    .{ .stage = .command_processor_ready, .fragment = "16CommandProcessor10InitializeE", .purpose = "GPU command processor bring-up" },
    .{ .stage = .complete_launch_started, .fragment = "8Emulator14CompleteLaunchE", .purpose = "the launch path that loads the title" },
    .{ .stage = .user_module_loaded, .fragment = "11KernelState19SetExecutableModuleE", .purpose = "wiring default.xex as the executable module" },
    .{ .stage = .precompile_requested, .fragment = "9XexModule10PrecompileE", .purpose = "entering the title's discovered-function precompile pass" },
    .{ .stage = .precompile_completed, .fragment = "9XexModule10PrecompileE", .purpose = "returning from the title's discovered-function precompile pass" },
    .{ .stage = .user_module_ready, .fragment = "11KernelState23FinishLoadingUserModuleE", .purpose = "completing user module load" },
    .{ .stage = .shader_storage_requested, .fragment = "14GraphicsSystem23InitializeShaderStorageE", .purpose = "entering per-title shader storage initialization" },
    // The stage the current run stops at. Its implementation being present is
    // exactly what distinguishes "the code is missing" from "the code is never
    // called", and those need different fixes.
    .{ .stage = .shader_storage_ready, .fragment = "14GraphicsSystem23InitializeShaderStorageE", .purpose = "per-title shader storage initialization" },
    .{ .stage = .guest_main_ready, .fragment = "11KernelState12LaunchModuleE", .purpose = "starting the guest main thread" },
};

/// Functions the contract does not name a stage for, but whose absence would
/// make the run fail later and less legibly.
pub const symbol_units = [_]SymbolUnit{
    .{ .fragment = "9XexModule10PrecompileE", .purpose = "ahead-of-time translation of discovered guest functions" },
    .{ .fragment = "9XexModule12LoadContinueE", .purpose = "XEX image load" },
    .{ .fragment = "3gpu16CommandProcessor13ExecutePacketE", .purpose = "guest command ring execution", .required = false },
    .{ .fragment = "2ui9Presenter", .purpose = "host presentation", .required = false },
};

/// Host capabilities named by the probe rather than by the image.
pub const HostUnit = struct {
    name: []const u8,
    purpose: []const u8,
    required: bool = true,
};

pub const host_units = [_]HostUnit{
    .{ .name = "decoder-audit", .purpose = "the x86-64 decoder handles the encodings this image contains" },
    .{ .name = "vex-safety", .purpose = "VEX encodings are decodable or provably absent", .required = false },
    .{ .name = "vulkan-loader", .purpose = "a Vulkan loader is present for the graphics path", .required = false },
    .{ .name = "window-system", .purpose = "a native window can be created for presentation", .required = false },
};

/// A file the run reads or writes, declared with the shape it must have.
pub const AssetUnit = struct {
    path: []const u8,
    kind: plan.AssetKind,
    purpose: []const u8,
    required: bool = true,
};

/// Build the image-structure units. These are the cheapest and the most
/// fundamental, so they run first: nothing below them means anything if the
/// image itself is not what it claims to be.
pub fn addImageUnits(target: *plan.Plan) void {
    target.add(.{ .category = .image, .name = "mach-o-header", .purpose = "the file is a mapped 64-bit Mach-O image" });
    target.add(.{ .category = .image, .name = "entry-point", .purpose = "the image declares an entry point" });
    target.add(.{ .category = .image, .name = "text-segment", .purpose = "an executable text segment is mapped" });
    target.add(.{ .category = .image, .name = "symbol-table", .purpose = "a symbol table is present for contract resolution" });
    target.add(.{ .category = .image, .name = "bundle-executable", .purpose = "the image is the app bundle's executable", .required = false });
}

pub fn addHostUnits(target: *plan.Plan) void {
    for (host_units) |unit| {
        target.add(.{
            .category = .host,
            .name = unit.name,
            .purpose = unit.purpose,
            .required = unit.required,
        });
    }
}

pub fn addSymbolUnits(target: *plan.Plan) void {
    for (symbol_units) |unit| {
        target.add(.{
            .category = .symbol,
            .name = unit.fragment,
            .purpose = unit.purpose,
            .required = unit.required,
        });
    }
}

/// One contract unit per stage, plus a reachability unit for each.
///
/// They are separate units on purpose. "The code is missing" and "the code is
/// present and nothing calls it" have different causes and different fixes,
/// and collapsing them into one verdict loses exactly the distinction the
/// reader needs.
pub fn addContractUnits(target: *plan.Plan) void {
    for (contract_units) |unit| {
        target.add(.{
            .category = .symbol,
            .name = unit.fragment,
            .purpose = unit.purpose,
        });
    }
    for (contract_units) |unit| {
        target.add(.{
            .category = .contract,
            .name = @tagName(unit.stage),
            .implementation = unit.fragment,
            .purpose = unit.purpose,
            .required = unit.reachability_required,
        });
    }
}

pub fn addAssetUnits(target: *plan.Plan, assets: []const AssetUnit) void {
    for (assets) |unit| {
        target.add(.{
            .category = .asset,
            .name = unit.path,
            .purpose = unit.purpose,
            .required = unit.required,
            .asset_kind = unit.kind,
        });
    }
}

/// Assemble the whole plan in the order the run will need it.
pub fn build(target: *plan.Plan, assets: []const AssetUnit) void {
    addImageUnits(target);
    addHostUnits(target);
    addAssetUnits(target, assets);
    addSymbolUnits(target);
    addContractUnits(target);
}

test "the plan covers every stage the contract requires before graphics" {
    var built = plan.Plan{};
    build(&built, &.{});
    try std.testing.expect(built.count > 20);
    try std.testing.expectEqual(@as(usize, 0), built.dropped);

    // The stage the current run stops at must be represented, or the plan
    // cannot answer the question that matters right now.
    var saw_shader_storage = false;
    var saw_user_module_ready = false;
    for (built.units()) |record| {
        if (record.unit.category != .contract) continue;
        if (std.mem.eql(u8, record.unit.name, "shader_storage_ready")) saw_shader_storage = true;
        if (std.mem.eql(u8, record.unit.name, "user_module_ready")) saw_user_module_ready = true;
    }
    try std.testing.expect(saw_shader_storage);
    try std.testing.expect(saw_user_module_ready);
}

test "image units come first so nothing is judged against an unusable image" {
    var built = plan.Plan{};
    build(&built, &.{});
    try std.testing.expectEqual(plan.UnitCategory.image, built.units()[0].unit.category);
    try std.testing.expectEqualStrings("mach-o-header", built.units()[0].unit.name);
}

test "every contract unit names an implementation to resolve" {
    for (contract_units) |unit| {
        try std.testing.expect(unit.fragment.len != 0);
        try std.testing.expect(unit.purpose.len != 0);
        // A fragment must carry its Itanium length prefix, or it would match
        // far more broadly than intended.
        try std.testing.expect(unit.fragment[0] >= '0' and unit.fragment[0] <= '9');
    }
}

test "asset units carry the shape the file must have" {
    var built = plan.Plan{};
    const assets = [_]AssetUnit{
        .{ .path = "/disc.iso", .kind = .disc_image, .purpose = "the title disc" },
        .{ .path = "/cache", .kind = .writable_directory, .purpose = "shader cache", .required = false },
    };
    build(&built, &assets);
    var disc_kind: ?plan.AssetKind = null;
    for (built.units()) |record| {
        if (record.unit.category != .asset) continue;
        if (std.mem.eql(u8, record.unit.name, "/disc.iso")) disc_kind = record.unit.asset_kind;
    }
    try std.testing.expectEqual(plan.AssetKind.disc_image, disc_kind orelse return error.TestUnexpectedResult);
}

/// Validate an Itanium name fragment against its own length prefixes.
///
/// A fragment is a chain of `<length><identifier>` components. Miscounting one
/// prefix produces a fragment that matches nothing, which turns a real
/// precondition check into a guaranteed false failure — and because the plan
/// halts on a required unit, that would refuse every launch. Three of these
/// were wrong when the list was first written, so the arithmetic is checked
/// rather than trusted.
pub fn fragmentIsWellFormed(fragment: []const u8) bool {
    var index: usize = 0;
    var components: usize = 0;
    while (index < fragment.len) {
        if (fragment[index] == 'E') {
            index += 1;
            continue;
        }
        if (fragment[index] < '0' or fragment[index] > '9') return false;
        var length: usize = 0;
        while (index < fragment.len and fragment[index] >= '0' and fragment[index] <= '9') {
            length = length * 10 + (fragment[index] - '0');
            index += 1;
        }
        if (length == 0) return false;
        // The identifier must actually be present and that long. A trailing
        // component may be cut short by the fragment ending, which is only
        // legal when it consumes the entire remainder.
        if (index + length > fragment.len) return false;
        index += length;
        components += 1;
    }
    return components != 0;
}

test "every symbol fragment agrees with its own Itanium length prefixes" {
    for (contract_units) |unit| {
        std.testing.expect(fragmentIsWellFormed(unit.fragment)) catch |err| {
            std.debug.print("malformed contract fragment: {s}\n", .{unit.fragment});
            return err;
        };
    }
    for (symbol_units) |unit| {
        std.testing.expect(fragmentIsWellFormed(unit.fragment)) catch |err| {
            std.debug.print("malformed symbol fragment: {s}\n", .{unit.fragment});
            return err;
        };
    }
}

test "the static plan has a nonzero content fingerprint" {
    try std.testing.expect(fingerprint() != 0);
}

test "the length-prefix check rejects the mistakes it exists for" {
    // Correct: "InitializeKernelGuestGlobals" is 28 characters.
    try std.testing.expect(fragmentIsWellFormed("11KernelState28InitializeKernelGuestGlobalsE"));
    // The original mistake: 30 overruns the identifier and matches nothing.
    try std.testing.expect(!fragmentIsWellFormed("11KernelState30InitializeKernelGuestGlobalsE"));
    try std.testing.expect(!fragmentIsWellFormed("11KernelState16LaunchModuleE"));
    try std.testing.expect(fragmentIsWellFormed("11KernelState12LaunchModuleE"));
    // A fragment with no length prefix at all would match far too broadly.
    try std.testing.expect(!fragmentIsWellFormed("LaunchModule"));
}
