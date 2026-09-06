//! Rosette's ownership map for Xenia's `src/xenia/scripts` directory.
//!
//! The files in that directory are an external reference surface. They are
//! not a second build system for Rosette. This package records every source
//! script, the Rosette adapter that owns its policy, and the small set of
//! scripts that historically selected or provisioned x86brew. The shell
//! adapters do host I/O; this package is only immutable vocabulary and drift
//! detection.

const std = @import("std");

pub const schema_version: u32 = 1;

pub const Adapter = enum(u8) {
    environment,
    toolchain,
    gtk,
    compiler,
    linker,
    dxil,
    vulkan,
    diagnostics,
    orchestration,
    project,
    signing,

    pub fn label(self: Adapter) []const u8 {
        return switch (self) {
            .environment => "environment",
            .toolchain => "toolchain",
            .gtk => "gtk",
            .compiler => "compiler",
            .linker => "linker",
            .dxil => "dxil",
            .vulkan => "vulkan",
            .diagnostics => "diagnostics",
            .orchestration => "orchestration",
            .project => "project",
            .signing => "signing",
        };
    }
};

pub const Script = struct {
    source_path: []const u8,
    adapter: Adapter,
    packaged_path: []const u8,
    /// True when the old script selected, created, or injected an x86brew
    /// path. These are the scripts whose policy must not remain in Xenia.
    x86brew_policy: bool = false,
};

const environment = "tools/xenia/scripts/rosette-xenia-environment.sh";
const toolchain = "tools/xenia/scripts/rosette-xenia-toolchain.sh";
const gtk = "tools/xenia/scripts/rosette-xenia-gtk.sh";
const compiler = "tools/xenia/scripts/rosette-xenia-compiler.sh";
const linker = "tools/xenia/scripts/rosette-xenia-linker.sh";
const dxil = "tools/xenia/scripts/rosette-xenia-dxil.sh";
const vulkan = "tools/xenia/scripts/rosette-xenia-vulkan.sh";
const diagnostics = "tools/xenia/scripts/rosette-xenia-diagnostics.sh";
const orchestration = "tools/xenia/scripts/rosette-xenia-orchestration.sh";
const project = "tools/xenia/scripts/rosette-xenia-project.sh";
const signing = "tools/xenia/scripts/rosette-xenia-signing.sh";

/// Complete inventory of the external target directory. Keep this list in
/// source order so the manifest is easy to compare with Xenia's README.
pub const scripts = [_]Script{
    .{ .source_path = "src/xenia/scripts/analyze-memory-patterns.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/avx-and-compat-test.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/build-wrapper.sh", .adapter = .orchestration, .packaged_path = orchestration },
    .{ .source_path = "src/xenia/scripts/build-xenia-macos.sh", .adapter = .toolchain, .packaged_path = toolchain, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/capstone-search-pattern-for-arm64.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/check_entitlements.sh", .adapter = .signing, .packaged_path = signing },
    .{ .source_path = "src/xenia/scripts/clang_gtk_wrapper.sh", .adapter = .compiler, .packaged_path = compiler, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/configure_xcode_gtk.sh", .adapter = .gtk, .packaged_path = gtk, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/create_clean_project.sh", .adapter = .project, .packaged_path = project },
    .{ .source_path = "src/xenia/scripts/entitlements_fix_3840.sh", .adapter = .signing, .packaged_path = signing },
    .{ .source_path = "src/xenia/scripts/moltenvk-vulkan-diagnostic.sh", .adapter = .vulkan, .packaged_path = vulkan, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/monitor-memory-live.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/run-all-diagnostics.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/run-wrapper.sh", .adapter = .orchestration, .packaged_path = orchestration },
    .{ .source_path = "src/xenia/scripts/setup-x86brew.sh", .adapter = .environment, .packaged_path = environment, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/setup_dxil_cmake_deps.sh", .adapter = .dxil, .packaged_path = dxil },
    .{ .source_path = "src/xenia/scripts/setup_xcode_gtk.sh", .adapter = .gtk, .packaged_path = gtk, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/shader-compilation-diagnostic.sh", .adapter = .vulkan, .packaged_path = vulkan },
    .{ .source_path = "src/xenia/scripts/sign-xenia-macos.sh", .adapter = .signing, .packaged_path = signing },
    .{ .source_path = "src/xenia/scripts/startup-starvation-triage.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/status-wrapper.sh", .adapter = .orchestration, .packaged_path = orchestration },
    .{ .source_path = "src/xenia/scripts/validate-moltenvk-env.sh", .adapter = .vulkan, .packaged_path = vulkan, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/validate_jit.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/vmx-detection-diagnostic.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/x86-display-diagnostics.sh", .adapter = .diagnostics, .packaged_path = diagnostics },
    .{ .source_path = "src/xenia/scripts/xcode_build_wrapper.sh", .adapter = .toolchain, .packaged_path = toolchain, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/xcode_compiler_wrapper.sh", .adapter = .compiler, .packaged_path = compiler, .x86brew_policy = true },
    .{ .source_path = "src/xenia/scripts/xenia-linker-macos.sh", .adapter = .linker, .packaged_path = linker, .x86brew_policy = true },
};

pub const x86brew_script_count: usize = blk: {
    var count: usize = 0;
    for (scripts) |script| count += @intFromBool(script.x86brew_policy);
    break :blk count;
};

pub fn scriptFor(source_path: []const u8) ?Script {
    for (scripts) |script| {
        if (std.mem.eql(u8, script.source_path, source_path)) return script;
    }
    return null;
}

pub fn adapterFor(source_path: []const u8) ?Adapter {
    return if (scriptFor(source_path)) |script| script.adapter else null;
}

pub fn hasX86BrewPolicy(source_path: []const u8) bool {
    return if (scriptFor(source_path)) |script| script.x86brew_policy else false;
}

test "the complete source directory inventory is present in the contract" {
    try std.testing.expectEqual(@as(usize, 28), scripts.len);
    try std.testing.expectEqual(@as(usize, 10), x86brew_script_count);
    for (scripts, 0..) |script, index| {
        try std.testing.expect(std.mem.startsWith(u8, script.source_path, "src/xenia/scripts/"));
        try std.testing.expect(std.mem.startsWith(u8, script.packaged_path, "tools/xenia/scripts/"));
        for (scripts[0..index]) |previous| {
            try std.testing.expect(!std.mem.eql(u8, previous.source_path, script.source_path));
        }
    }
}

test "the x86brew surface resolves only through Rosette policy adapters" {
    try std.testing.expectEqual(Adapter.toolchain, adapterFor("src/xenia/scripts/build-xenia-macos.sh").?);
    try std.testing.expectEqual(Adapter.environment, adapterFor("src/xenia/scripts/setup-x86brew.sh").?);
    try std.testing.expectEqual(Adapter.gtk, adapterFor("src/xenia/scripts/setup_xcode_gtk.sh").?);
    try std.testing.expectEqual(Adapter.compiler, adapterFor("src/xenia/scripts/xcode_compiler_wrapper.sh").?);
    try std.testing.expectEqual(Adapter.linker, adapterFor("src/xenia/scripts/xenia-linker-macos.sh").?);
    try std.testing.expect(hasX86BrewPolicy("src/xenia/scripts/validate-moltenvk-env.sh"));
    try std.testing.expect(!hasX86BrewPolicy("src/xenia/scripts/validate_jit.sh"));
}

test "unknown Xenia scripts are rejected instead of falling through" {
    try std.testing.expect(scriptFor("src/xenia/scripts/not-a-real-script.sh") == null);
    try std.testing.expect(adapterFor("src/xenia/scripts/not-a-real-script.sh") == null);
    try std.testing.expect(!hasX86BrewPolicy("src/xenia/scripts/not-a-real-script.sh"));
}
