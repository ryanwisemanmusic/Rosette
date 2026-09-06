//! Rosette-owned macOS host contract for translated x86-64 builds.
//!
//! This package is deliberately policy and vocabulary only. It does not run
//! Homebrew, inspect the filesystem, or install a dependency. The shell
//! adapter and the runtime preflight are the only layers allowed to perform
//! those actions. Keeping the contract here prevents Xenia's historical
//! `/usr/local/x86brew` assumptions from becoming an implicit ABI.

const std = @import("std");

pub const schema_version: u32 = 1;
pub const x86_64_architecture = "x86_64";

/// Environment names shared by the Rosette shell adapter and runtime probes.
/// They are constants rather than duplicated string literals so a renamed
/// host root cannot silently split the build and runtime configurations.
pub const host_root_environment = "ROSETTE_MACOS_HOST_ROOT";
pub const host_prefix_environment = "ROSETTE_HOST_PREFIX";
pub const compiler_environment = "ROSETTE_CC";
pub const cxx_compiler_environment = "ROSETTE_CXX";
pub const legacy_x86brew_prefix = "/usr/local/x86brew";
pub const system_x86_prefix = "/usr/local";
pub const arm_homebrew_prefix = "/opt/homebrew";

/// A dependency that belongs to the x86-64 Xenia/Rosette build environment.
/// The package does not claim that every target needs every item at runtime;
/// it makes the expected surface explicit for a provider audit.
pub const Dependency = enum(u8) {
    clang,
    clangxx,
    cmake,
    nasm,
    pkg_config,
    sdl2,
    gtk3,
    fontconfig,
    vulkan_headers,
    vulkan_loader,

    pub fn label(self: Dependency) []const u8 {
        return switch (self) {
            .clang => "clang",
            .clangxx => "clang++",
            .cmake => "cmake",
            .nasm => "nasm",
            .pkg_config => "pkg-config",
            .sdl2 => "SDL2",
            .gtk3 => "GTK+3",
            .fontconfig => "fontconfig",
            .vulkan_headers => "Vulkan-Headers",
            .vulkan_loader => "Vulkan loader",
        };
    }
};

pub const required_dependencies = [_]Dependency{
    .clang,
    .clangxx,
    .cmake,
    .nasm,
    .pkg_config,
    .sdl2,
    .gtk3,
    .fontconfig,
    .vulkan_headers,
    .vulkan_loader,
};

/// The source class of a toolchain path. `/usr/local` remains a compatibility
/// provider, but it is named separately from Rosette's managed root so a
/// migration away from x86brew can be measured rather than guessed.
pub const Provider = enum(u8) {
    rosette_managed,
    legacy_x86brew,
    system_x86,
    arm_homebrew,
    other,

    pub fn label(self: Provider) []const u8 {
        return switch (self) {
            .rosette_managed => "rosette-managed",
            .legacy_x86brew => "legacy-x86brew",
            .system_x86 => "system-x86",
            .arm_homebrew => "arm-homebrew",
            .other => "other",
        };
    }
};

/// The host JIT contract is intentionally explicit about what Rosette does.
/// Xenia asks for MAP_JIT-compatible storage, but its generated x86 bytes are
/// guest code consumed by Rosette; the ARM host must not execute them as if
/// they were native ARM instructions. A successful run therefore proves
/// storage and metadata invariants, not native host execution of x86 bytes.
pub const JitContract = struct {
    map_jit_storage_required: bool = true,
    os_selected_trampoline_required: bool = true,
    guest_code_executed_by_rosette: bool = true,
    host_execute_guest_x86: bool = false,
    low_address_metadata_required: bool = true,
    writable_executable_host_alias_forbidden: bool = true,

    pub fn coherent(self: JitContract) bool {
        return self.map_jit_storage_required and
            self.os_selected_trampoline_required and
            self.guest_code_executed_by_rosette and
            !self.host_execute_guest_x86 and
            self.low_address_metadata_required and
            self.writable_executable_host_alias_forbidden;
    }
};

pub const x86_64_jit_contract = JitContract{};

/// Vulkan loaders are host-native providers. Unlike the x86 build tools, a
/// native ARM Vulkan loader under `/opt/homebrew` is a valid provider for a
/// native Rosette process, so it must not be rejected by the x86 toolchain
/// path policy below.
pub const vulkan_loader_default_paths = [_][]const u8{
    "/usr/local/lib/libvulkan.1.dylib",
    "/usr/local/lib/libvulkan.dylib",
    "/opt/homebrew/lib/libvulkan.1.dylib",
    "/opt/homebrew/lib/libvulkan.dylib",
};

pub const vulkan_loader_suffixes = [_][]const u8{
    "lib/libvulkan.1.dylib",
    "lib/libvulkan.dylib",
    "macOS/lib/libvulkan.1.dylib",
    "macOS/lib/libvulkan.dylib",
    "native/lib/libvulkan.1.dylib",
    "native/lib/libvulkan.dylib",
    "x86_64/lib/libvulkan.1.dylib",
    "x86_64/lib/libvulkan.dylib",
};

/// Runtime discovery must not mistake a managed x86_64 loader for the loader
/// Rosette itself can load. The broad suffix list above is retained for host
/// provider audits, while this list is the native-runtime boundary: it only
/// names roots that may contain a host-native Vulkan loader.
pub const native_vulkan_loader_suffixes = [_][]const u8{
    "lib/libvulkan.1.dylib",
    "lib/libvulkan.dylib",
    "macOS/lib/libvulkan.1.dylib",
    "macOS/lib/libvulkan.dylib",
    "native/lib/libvulkan.1.dylib",
    "native/lib/libvulkan.dylib",
};

fn pathPrefix(path: []const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    return path.len == prefix.len or (path.len > prefix.len and path[prefix.len] == '/');
}

pub fn isArmHomebrewPath(path: []const u8) bool {
    return pathPrefix(path, arm_homebrew_prefix);
}

pub fn isLegacyX86brewPath(path: []const u8) bool {
    return pathPrefix(path, legacy_x86brew_prefix);
}

pub fn isSystemX86Path(path: []const u8) bool {
    return pathPrefix(path, system_x86_prefix);
}

pub fn isRosetteManagedPath(path: []const u8, managed_root: []const u8) bool {
    return managed_root.len != 0 and pathPrefix(path, managed_root);
}

pub fn classifyProvider(path: []const u8, managed_root: []const u8) Provider {
    if (isRosetteManagedPath(path, managed_root)) return .rosette_managed;
    if (isArmHomebrewPath(path)) return .arm_homebrew;
    if (isLegacyX86brewPath(path)) return .legacy_x86brew;
    if (isSystemX86Path(path)) return .system_x86;
    return .other;
}

/// An x86 build must never resolve tools or libraries from ARM Homebrew. Xcode
/// and a Rosette-managed provider are both valid, as is the legacy x86brew
/// prefix during migration. The caller still has to verify the binary's
/// architecture; this function only rejects the known wrong prefix.
pub fn usableForX86Toolchain(path: []const u8, managed_root: []const u8) bool {
    _ = managed_root;
    return path.len != 0 and !isArmHomebrewPath(path);
}

/// Join a provider root and a relative suffix without allocating. This keeps
/// path construction in the contract's vocabulary while allowing callers to
/// use a stack buffer and preserve their own I/O policy.
pub fn joinPath(root: []const u8, suffix: []const u8, buffer: []u8) ?[]const u8 {
    if (root.len == 0 or suffix.len == 0) return null;
    var root_len = root.len;
    while (root_len > 1 and root[root_len - 1] == '/') root_len -= 1;
    var suffix_start: usize = 0;
    while (suffix_start < suffix.len and suffix[suffix_start] == '/') suffix_start += 1;
    if (suffix_start == suffix.len) return null;
    const needs_separator = root_len != 0 and root[root_len - 1] != '/';
    const suffix_len = suffix.len - suffix_start;
    const total = root_len + @as(usize, if (needs_separator) 1 else 0) + suffix_len;
    if (total > buffer.len) return null;

    var cursor: usize = 0;
    @memcpy(buffer[cursor..][0..root_len], root[0..root_len]);
    cursor += root_len;
    if (needs_separator) {
        buffer[cursor] = '/';
        cursor += 1;
    }
    @memcpy(buffer[cursor..][0..suffix_len], suffix[suffix_start..]);
    return buffer[0..total];
}

test "macOS host contract keeps JIT storage policy coherent" {
    try std.testing.expect(x86_64_jit_contract.coherent());
    try std.testing.expect(x86_64_jit_contract.map_jit_storage_required);
    try std.testing.expect(!x86_64_jit_contract.host_execute_guest_x86);
}

test "x86 toolchain rejects ARM Homebrew but retains migration providers" {
    try std.testing.expect(!usableForX86Toolchain("/opt/homebrew/bin/clang", "/tmp/rosette-host"));
    try std.testing.expect(usableForX86Toolchain("/usr/local/x86brew/bin/nasm", "/tmp/rosette-host"));
    try std.testing.expect(usableForX86Toolchain("/tmp/rosette-host/x86_64/bin/nasm", "/tmp/rosette-host"));
    try std.testing.expectEqual(Provider.arm_homebrew, classifyProvider("/opt/homebrew/bin/clang", "/tmp/rosette-host"));
    try std.testing.expectEqual(Provider.legacy_x86brew, classifyProvider("/usr/local/x86brew/bin/nasm", "/tmp/rosette-host"));
    try std.testing.expectEqual(Provider.rosette_managed, classifyProvider("/tmp/rosette-host/x86_64/bin/nasm", "/tmp/rosette-host"));
}

test "host contract joins provider paths without allocation" {
    var buffer: [128]u8 = undefined;
    const joined = joinPath("/tmp/rosette-host/", "/x86_64/lib/libvulkan.dylib", &buffer) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("/tmp/rosette-host/x86_64/lib/libvulkan.dylib", joined);
    try std.testing.expect(joinPath("", "lib/tool", &buffer) == null);
    try std.testing.expect(joinPath("/tmp", "", &buffer) == null);
}

test "required dependency surface is stable" {
    try std.testing.expectEqual(@as(usize, 10), required_dependencies.len);
    try std.testing.expectEqualStrings("Vulkan loader", Dependency.vulkan_loader.label());
}

test "native Vulkan runtime paths exclude the x86-only provider" {
    for (native_vulkan_loader_suffixes) |suffix| {
        try std.testing.expect(std.mem.indexOf(u8, suffix, "x86_64") == null);
    }
    try std.testing.expectEqual(@as(usize, 6), native_vulkan_loader_suffixes.len);
}
