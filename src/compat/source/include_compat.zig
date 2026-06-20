const std = @import("std");

const CandidatePolicy = enum { direct_headers, header_root };

const CandidateDir = struct {
    subdir: []const u8,
    policy: CandidatePolicy,
};

const project_candidate_dirs = [_]CandidateDir{
    .{ .subdir = "", .policy = .direct_headers },
    .{ .subdir = "include", .policy = .header_root },
    .{ .subdir = "inc", .policy = .header_root },
    .{ .subdir = "src", .policy = .direct_headers },
    .{ .subdir = "lib", .policy = .direct_headers },
};
const package_candidate_dirs = [_]CandidateDir{
    .{ .subdir = "", .policy = .direct_headers },
    .{ .subdir = "include", .policy = .header_root },
    .{ .subdir = "inc", .policy = .header_root },
    .{ .subdir = "src", .policy = .direct_headers },
    .{ .subdir = "lib", .policy = .direct_headers },
};
const vendor_dir_names = [_][]const u8{ "third_party", "vendor", "external", "extern", "deps", "dependencies", "libraries" };

pub fn discoverIncludeDirs(io: std.Io, allocator: std.mem.Allocator, project_root: []const u8) !std.ArrayList([]const u8) {
    var dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (dirs.items) |dir| allocator.free(dir);
        dirs.deinit(allocator);
    }

    try appendCandidateDirs(io, allocator, &dirs, project_root, &project_candidate_dirs);

    for (vendor_dir_names) |vendor_name| {
        const vendor_root = try std.fs.path.join(allocator, &.{ project_root, vendor_name });
        defer allocator.free(vendor_root);
        if (!dirExists(io, vendor_root)) continue;

        var vendor_dir = std.Io.Dir.openDirAbsolute(io, vendor_root, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound, error.NotDir, error.AccessDenied => continue,
            else => |e| return e,
        };
        defer vendor_dir.close(io);

        var it = vendor_dir.iterate();
        while (it.next(io) catch null) |entry| {
            if (entry.kind != .directory and entry.kind != .sym_link) continue;
            const package_root = try std.fs.path.join(allocator, &.{ vendor_root, entry.name });
            defer allocator.free(package_root);
            try appendCandidateDirs(io, allocator, &dirs, package_root, &package_candidate_dirs);
        }
    }

    return dirs;
}

fn appendCandidateDirs(
    io: std.Io,
    allocator: std.mem.Allocator,
    dirs: *std.ArrayList([]const u8),
    base: []const u8,
    subdirs: []const CandidateDir,
) !void {
    for (subdirs) |entry| {
        const candidate = if (entry.subdir.len == 0)
            try allocator.dupe(u8, base)
        else
            try std.fs.path.join(allocator, &.{ base, entry.subdir });
        defer allocator.free(candidate);
        if (isUsableIncludeDir(io, allocator, candidate, entry.policy)) {
            try appendUniqueOwned(allocator, dirs, candidate);
        }
    }
}

fn appendUniqueOwned(allocator: std.mem.Allocator, dirs: *std.ArrayList([]const u8), candidate: []const u8) !void {
    for (dirs.items) |existing| {
        if (std.mem.eql(u8, existing, candidate)) return;
    }
    try dirs.append(allocator, try allocator.dupe(u8, candidate));
}

fn isUsableIncludeDir(io: std.Io, allocator: std.mem.Allocator, path: []const u8, policy: CandidatePolicy) bool {
    if (!dirExists(io, path)) return false;
    if (containsX86IntrinsicShadow(io, path)) return false;
    if (containsStandardHeaderShadow(io, path)) return false;
    if (containsImmediateHeader(io, path)) return true;
    return policy == .header_root and containsImmediateChildWithHeader(io, allocator, path);
}

fn dirExists(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

fn containsImmediateHeader(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (hasHeaderExtension(entry.name)) return true;
    }
    return false;
}

fn containsImmediateChildWithHeader(io: std.Io, allocator: std.mem.Allocator, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const child = std.fs.path.join(allocator, &.{ path, entry.name }) catch continue;
        defer allocator.free(child);
        if (containsImmediateHeader(io, child)) return true;
    }
    return false;
}

fn containsStandardHeaderShadow(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (isStandardHeaderShadowName(entry.name)) return true;
    }
    return false;
}

pub fn containsX86IntrinsicShadow(io: std.Io, path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true }) catch return false;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (isX86IntrinsicShadowHeaderName(entry.name)) return true;
    }
    return false;
}

pub fn hasHeaderExtension(name: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(name, ".h") or
        std.ascii.endsWithIgnoreCase(name, ".hh") or
        std.ascii.endsWithIgnoreCase(name, ".hpp") or
        std.ascii.endsWithIgnoreCase(name, ".hxx");
}

pub fn isStandardHeaderShadowName(name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '.') != null) return false;
    const headers = [_][]const u8{
        "algorithm",     "any",                "array",            "atomic",
        "barrier",       "bit",                "bitset",           "charconv",
        "chrono",        "codecvt",            "compare",          "complex",
        "concepts",      "condition_variable", "coroutine",        "cstddef",
        "cstdint",       "cstdio",             "cstdlib",          "cstring",
        "deque",         "exception",          "execution",        "filesystem",
        "format",        "forward_list",       "fstream",          "functional",
        "future",        "initializer_list",   "iomanip",          "ios",
        "iosfwd",        "iostream",           "istream",          "iterator",
        "latch",         "limits",             "list",             "locale",
        "map",           "memory",             "memory_resource",  "mutex",
        "new",           "numbers",            "numeric",          "optional",
        "ostream",       "queue",              "random",           "ranges",
        "ratio",         "regex",              "scoped_allocator", "semaphore",
        "set",           "shared_mutex",       "source_location",  "span",
        "sstream",       "stack",              "stdexcept",        "stop_token",
        "streambuf",     "string",             "string_view",      "strstream",
        "syncstream",    "system_error",       "thread",           "tuple",
        "type_traits",   "typeindex",          "typeinfo",         "unordered_map",
        "unordered_set", "utility",            "valarray",         "variant",
        "vector",        "version",
    };
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(name, header)) return true;
    }
    return false;
}

pub fn isX86IntrinsicShadowHeaderName(name: []const u8) bool {
    const headers = [_][]const u8{
        "adxintrin.h",
        "ammintrin.h",
        "avx2intrin.h",
        "avx512bfintrin.h",
        "avx512bitalgintrin.h",
        "avx512bwbf16vlintrin.h",
        "avx512bwintrin.h",
        "avx512cdintrin.h",
        "avx512dqintrin.h",
        "avx512erintrin.h",
        "avx512fintrin.h",
        "avx512fp16intrin.h",
        "avx512ifmainintrin.h",
        "avx512ifmavlintrin.h",
        "avx512pfintrin.h",
        "avx512vbmi2intrin.h",
        "avx512vbmiintrin.h",
        "avx512vlbitalgintrin.h",
        "avx512vlbwintrin.h",
        "avx512vldqintrin.h",
        "avx512vlintrin.h",
        "avx512vlvbmi2intrin.h",
        "avx512vlvnniintrin.h",
        "avx512vnniintrin.h",
        "avx512vp2intersectintrin.h",
        "avx512vpopcntdqintrin.h",
        "avx512vpopcntdqvlintrin.h",
        "avx512vpopcntintrin.h",
        "avx512vpopcntvlintrin.h",
        "avx512vpshufbitqmbintrin.h",
        "avxintrin.h",
        "avxintrin512.h",
        "bmi2intrin.h",
        "bmiintrin.h",
        "clflushoptintrin.h",
        "clwbintrin.h",
        "cpuid.h",
        "emmintrin.h",
        "f16cintrin.h",
        "fma4intrin.h",
        "fmaintrin.h",
        "fxsrintrin.h",
        "ia32intrin.h",
        "immintrin.h",
        "lwpintrin.h",
        "lzcntintrin.h",
        "mmintrin.h",
        "movdirintrin.h",
        "mwaitxintrin.h",
        "nmmintrin.h",
        "pconfigintrin.h",
        "pkuintrin.h",
        "pmmintrin.h",
        "popcntintrin.h",
        "prfchwintrin.h",
        "rdseedintrin.h",
        "rtmintrin.h",
        "serializeintrin.h",
        "sgxintrin.h",
        "shaintrin.h",
        "smmintrin.h",
        "tbmintrin.h",
        "tmmintrin.h",
        "uintrintrin.h",
        "vaesintrin.h",
        "vpclmulqdqintrin.h",
        "waitpkgintrin.h",
        "wbnoinvdintrin.h",
        "wmmintrin.h",
        "x86gprintrin.h",
        "x86intrin.h",
        "xmmintrin.h",
        "xopintrin.h",
    };
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(name, header)) return true;
    }
    return false;
}

/// Detect whether a directory acts as a CPU-SIMD architecture bridging layer
/// (e.g., x86 SSE → ARM NEON emulation). Such directories cause `#error`
/// failures when the compiler targets an architecture that natively supports
/// the emulated ISA, because the bridging headers conflict with native ones.
///
/// Detection is by directory name pattern matching — any directory whose name
/// matches known SIMD bridging/emulation naming conventions is flagged. This
/// is a general rule: it handles any library that follows these conventions,
/// not just a hardcoded list of known projects.
pub fn isSimdBridgeDir(name: []const u8) bool {
    var buf: [256]u8 = undefined;
    const len = @min(name.len, buf.len);
    for (name[0..len], 0..) |ch, i| buf[i] = std.ascii.toLower(ch);
    const lowered = buf[0..len];
    if (std.mem.indexOf(u8, lowered, "2neon")) |_| return true;
    if (std.mem.indexOf(u8, lowered, "toneon")) |_| return true;
    return false;
}

pub fn pathContainsSimdBridgeDir(path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |component| {
        if (component.len > 0 and isSimdBridgeDir(component)) return true;
    }
    return false;
}

test "isSimdBridgeDir recognises known emulation layer names" {
    try std.testing.expect(isSimdBridgeDir("AvxToNeon"));
    try std.testing.expect(isSimdBridgeDir("sse2neon"));
    try std.testing.expect(isSimdBridgeDir("vex2NEON"));
    try std.testing.expect(isSimdBridgeDir("ymm2NEON"));
    try std.testing.expect(isSimdBridgeDir("bmi2NEON"));
    try std.testing.expect(isSimdBridgeDir("ppcFloat2NEON"));
    try std.testing.expect(!isSimdBridgeDir("simde"));
    try std.testing.expect(!isSimdBridgeDir("xsimd"));
    try std.testing.expect(!isSimdBridgeDir("zstd"));
    try std.testing.expect(!isSimdBridgeDir("Vulkan-Headers"));
    try std.testing.expect(!isSimdBridgeDir("capstone"));
    try std.testing.expect(pathContainsSimdBridgeDir("/tmp/third_party/AvxToNeon"));
    try std.testing.expect(!pathContainsSimdBridgeDir("/tmp/third_party/simde"));
}

test "header extension detection covers C and C++ headers" {
    try std.testing.expect(hasHeaderExtension("zstd.h"));
    try std.testing.expect(hasHeaderExtension("reader.HPP"));
    try std.testing.expect(!hasHeaderExtension("zstd.c"));
}

test "standard library extensionless headers are treated as unsafe shadows" {
    try std.testing.expect(isStandardHeaderShadowName("version"));
    try std.testing.expect(isStandardHeaderShadowName("VERSION"));
    try std.testing.expect(isStandardHeaderShadowName("type_traits"));
    try std.testing.expect(!isStandardHeaderShadowName("version.h"));
    try std.testing.expect(!isStandardHeaderShadowName("project-version"));
}

test "x86 intrinsic shadow headers are detected separately from bridge entry headers" {
    try std.testing.expect(isX86IntrinsicShadowHeaderName("emmintrin.h"));
    try std.testing.expect(isX86IntrinsicShadowHeaderName("IMMINTRIN.H"));
    try std.testing.expect(isX86IntrinsicShadowHeaderName("cpuid.h"));
    try std.testing.expect(!isX86IntrinsicShadowHeaderName("vex2neon.h"));
    try std.testing.expect(!isX86IntrinsicShadowHeaderName("bmi2neon.h"));
    try std.testing.expect(!isX86IntrinsicShadowHeaderName("ppcfloat2neon.h"));
}
