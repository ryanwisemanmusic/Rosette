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

fn fileExistsAbsolute(io: std.Io, path: []const u8) bool {
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
    file.close(io);
    return true;
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

/// Detect whether a source tree uses capstone (or similar ARM/ARM64
/// disassembly libraries) whose enum types need forcing to plain int
/// on Apple Clang in C++ mode.  When true, force-including
/// `shims/macos/force_types.h` (or adding `-include`) is recommended.
pub fn detectCapstoneUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.basename;
        if (!hasHeaderExtension(name) and
            !std.ascii.endsWithIgnoreCase(name, ".c") and
            !std.ascii.endsWithIgnoreCase(name, ".cc") and
            !std.ascii.endsWithIgnoreCase(name, ".cpp") and
            !std.ascii.endsWithIgnoreCase(name, ".cxx") and
            !std.ascii.endsWithIgnoreCase(name, ".m") and
            !std.ascii.endsWithIgnoreCase(name, ".mm"))
            continue;
        const content = entry.dir.readFileAlloc(io, name, allocator, .limited(32 * 4096)) catch continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "#include <capstone")) |_| return true;
        if (std.mem.indexOf(u8, content, "#include \"capstone")) |_| return true;
        if (std.mem.indexOf(u8, content, "arm_cc") != null and
            std.mem.indexOf(u8, content, "arm64_cc") != null and
            std.mem.indexOf(u8, content, "arm_reg") != null and
            std.mem.indexOf(u8, content, "arm64_reg") != null)
            return true;
    }
    return false;
}

/// Detect whether a source tree references LLVM bitcode parsing code
/// that may be incompatible on the current platform.  When true, the
/// Zig stub at `compat/source/bitcode_stub.zig` can be linked instead
/// of the incompatible C++ implementation.
pub fn detectBitcodeParserUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.basename;
        if (!hasHeaderExtension(name) and
            !std.ascii.endsWithIgnoreCase(name, ".c") and
            !std.ascii.endsWithIgnoreCase(name, ".cc") and
            !std.ascii.endsWithIgnoreCase(name, ".cpp") and
            !std.ascii.endsWithIgnoreCase(name, ".cxx"))
            continue;
        const content = entry.dir.readFileAlloc(io, name, allocator, .limited(32 * 4096)) catch continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "LLVMBitcodeParser")) |_| return true;
        if (std.mem.indexOf(u8, content, "BitcodeParser")) |_| return true;
    }
    return false;
}

fn hasHeaderExtension(name: []const u8) bool {
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

pub fn isSimdFacadeDir(name: []const u8) bool {
    var buf: [256]u8 = undefined;
    const len = @min(name.len, buf.len);
    for (name[0..len], 0..) |ch, i| buf[i] = std.ascii.toLower(ch);
    const lowered = buf[0..len];
    return std.mem.eql(u8, lowered, "simde") or
        std.mem.eql(u8, lowered, "xsimd");
}

pub fn isSimdCompatibilityDir(name: []const u8) bool {
    return isSimdBridgeDir(name) or isSimdFacadeDir(name);
}

pub fn pathContainsSimdCompatibilityDir(path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |component| {
        if (component.len > 0 and isSimdCompatibilityDir(component)) return true;
    }
    return false;
}

/// Generalized detection and compatibility helpers for macOS third-party
/// C/C++ compilation issues.  Each function maps to one or more patches
/// in patch/ and can be eliminated via compat headers (in include/shims/macos/)
/// or compiler flags.
fn isSourceOrHeaderFile(name: []const u8) bool {
    return hasHeaderExtension(name) or
        std.ascii.endsWithIgnoreCase(name, ".c") or
        std.ascii.endsWithIgnoreCase(name, ".cc") or
        std.ascii.endsWithIgnoreCase(name, ".cpp") or
        std.ascii.endsWithIgnoreCase(name, ".cxx") or
        std.ascii.endsWithIgnoreCase(name, ".m") or
        std.ascii.endsWithIgnoreCase(name, ".mm");
}

fn readFileContent(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir, basename: []const u8) ?[]const u8 {
    const content = dir.readFileAlloc(io, basename, allocator, .limited(256 * 1024)) catch return null;
    return content;
}

/// Detect whether a source directory uses `#include <endian.h>` in any of
/// its C/C++ source or header files.  On macOS, <endian.h> does not exist
/// natively; include/shims/macos/endian.h provides a general compat shim.
pub fn scanForEndianHeaderUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "#include <endian.h>")) |_| return true;
        if (std.mem.indexOf(u8, content, "#include <machine/endian.h>")) |_| return true;
    }
    return false;
}

/// Detect whether a source directory uses the `asm` keyword instead of
/// `__asm__`.  Apple Clang rejects bare `asm` in non-GNU C++ modes.
pub fn scanForAsmKeyword(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "asm (")) |_| return true;
        if (std.mem.indexOf(u8, content, "asm\n(")) |_| return true;
        if (std.mem.indexOf(u8, content, "asm volatile")) |_| return true;
        if (std.mem.indexOf(u8, content, "asm __volatile")) |_| return true;
    }
    return false;
}

/// Detect whether a library uses angle-bracket includes (`#include <...>`)
/// that refer to its own internal headers rather than external system headers.
/// Matching files are those where the included path (everything between `<` and
/// `>`) points to a file whose basename appears within the same source tree.
/// Such includes need either `-I` pointing at the package root or conversion
/// to quotes.
pub fn scanForAngleBracketLocalIncludes(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, content, pos, "#include <")) |start| {
            const after_open = start + "#include <".len;
            const close = std.mem.indexOfScalarPos(u8, content, after_open, '>') orelse break;
            const included = content[after_open..close];
            pos = close + 1;
            const last_slash = std.mem.lastIndexOfScalar(u8, included, '/') orelse continue;
            const basename = included[last_slash + 1 ..];
            if (basename.len == 0) continue;
            if (std.mem.indexOf(u8, entry.path, included[0..last_slash])) |_| return true;
        }
    }
    return false;
}

pub fn discoverAngleBracketIncludeDirs(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) !std.ArrayList([]const u8) {
    var dirs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (dirs.items) |owned| allocator.free(owned);
        dirs.deinit(allocator);
    }

    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return dirs;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return dirs;
    defer walker.deinit();

    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);

        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, content, pos, "#include <")) |start| {
            const after_open = start + "#include <".len;
            const close = std.mem.indexOfScalarPos(u8, content, after_open, '>') orelse break;
            const included = content[after_open..close];
            pos = close + 1;
            if (isLikelySystemAngleInclude(included)) continue;
            try appendLocalAngleIncludeDir(io, allocator, &dirs, dir_path, entry.path, included);
        }
    }

    return dirs;
}

fn appendLocalAngleIncludeDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    dirs: *std.ArrayList([]const u8),
    root: []const u8,
    source_rel_path: []const u8,
    included: []const u8,
) !void {
    if (included.len == 0) return;

    if (std.fs.path.dirname(source_rel_path)) |source_rel_dir| {
        const source_abs_dir = try std.fs.path.join(allocator, &.{ root, source_rel_dir });
        defer allocator.free(source_abs_dir);
        try appendIncludeRootIfHeaderExists(io, allocator, dirs, source_abs_dir, included);
    } else {
        try appendIncludeRootIfHeaderExists(io, allocator, dirs, root, included);
    }

    try appendIncludeRootIfHeaderExists(io, allocator, dirs, root, included);

    const subdirs = [_][]const u8{ "include", "inc", "src", "lib" };
    for (subdirs) |subdir| {
        const candidate_root = try std.fs.path.join(allocator, &.{ root, subdir });
        defer allocator.free(candidate_root);
        try appendIncludeRootIfHeaderExists(io, allocator, dirs, candidate_root, included);
    }
}

fn appendIncludeRootIfHeaderExists(
    io: std.Io,
    allocator: std.mem.Allocator,
    dirs: *std.ArrayList([]const u8),
    include_root: []const u8,
    included: []const u8,
) !void {
    const candidate = try std.fs.path.join(allocator, &.{ include_root, included });
    defer allocator.free(candidate);
    if (!fileExistsAbsolute(io, candidate)) return;
    try appendUniqueOwned(allocator, dirs, include_root);
}

fn isLikelySystemAngleInclude(included: []const u8) bool {
    if (included.len == 0) return true;
    if (std.mem.indexOfScalar(u8, included, '/') != null) {
        const system_prefixes = [_][]const u8{
            "arpa/",
            "CoreFoundation/",
            "dispatch/",
            "mach/",
            "machine/",
            "net/",
            "netinet/",
            "objc/",
            "pthread/",
            "sys/",
        };
        for (system_prefixes) |prefix| {
            if (std.mem.startsWith(u8, included, prefix)) return true;
        }
        return false;
    }
    return isStandardHeaderShadowName(included) or isCSystemHeaderName(included);
}

fn isCSystemHeaderName(name: []const u8) bool {
    const headers = [_][]const u8{
        "assert.h",    "complex.h",  "ctype.h",       "errno.h",    "fenv.h",
        "float.h",     "inttypes.h", "iso646.h",      "limits.h",   "locale.h",
        "math.h",      "setjmp.h",   "signal.h",      "stdalign.h", "stdarg.h",
        "stdatomic.h", "stdbit.h",   "stdbool.h",     "stddef.h",   "stdint.h",
        "stdio.h",     "stdlib.h",   "stdnoreturn.h", "string.h",   "tgmath.h",
        "threads.h",   "time.h",     "uchar.h",       "wchar.h",    "wctype.h",
    };
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(name, header)) return true;
    }
    return false;
}

/// Detect whether a source tree has patterns that typically trigger
/// -Wshorten-64-to-32 on LP64 platforms (macOS ARM64, Linux ARM64).
/// This includes explicit cast-to-32-bit patterns around function calls
/// that return `unsigned long` or `size_t`, and pointer-difference
/// narrowing to 32-bit types.
pub fn scanForShorten64To32Risk(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        const patterns = [_][]const u8{
            "(uint32_t)",
            "(u_int32_t)",
            "static_cast<uint32_t>",
            "static_cast<UINT4>",
            "static_cast<int>(",
            "(guint)",
            "static_cast<guint>",
        };
        for (patterns) |pat| {
            if (std.mem.indexOf(u8, content, pat)) |_| return true;
        }
    }
    return false;
}

/// Detect whether a source directory uses stb-style assertion macros
/// (STBTT_assert, STBI_ASSERT, etc.) that abort on failure in debug
/// builds.  macOS/Clang debug builds of bundled third-party libraries
/// frequently hit runtime assertions on valid-but-unusual input.
/// include/shims/macos/stb_compat.h redefines these as no-ops.
pub fn scanForStbAssertUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    const patterns = [_][]const u8{
        "STBTT_assert",
        "STBI_ASSERT",
        "STBIW_ASSERT",
        "STBV_ASSERT",
        "STBRP_ASSERT",
    };
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        for (patterns) |pat| {
            if (std.mem.indexOf(u8, content, pat)) |_| return true;
        }
    }
    return false;
}

/// Detect whether a source directory references `secure_getenv`.
/// macOS does not provide this GNU extension; `posix_compat.h` defines
/// it as `getenv(name)`.  Projects like Xenia's GTK windowed app and
/// any Linux-originated code that uses `secure_getenv` need this shim.
pub fn scanForSecureGetenvUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "secure_getenv")) |_| return true;
    }
    return false;
}

/// Detect whether a source directory uses the `ATOMIC_VAR_INIT` macro.
/// This C11 macro was removed in C17 and may not be defined by Apple
/// Clang.  `posix_compat.h` provides a no-op fallback.
pub fn scanForAtomicVarInitUsage(io: std.Io, allocator: std.mem.Allocator, dir_path: []const u8) bool {
    var dir = std.Io.Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    var walker = dir.walk(allocator) catch return false;
    defer walker.deinit();
    while (walker.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isSourceOrHeaderFile(entry.basename)) continue;
        const content = readFileContent(io, allocator, entry.dir, entry.basename) orelse continue;
        defer allocator.free(content);
        if (std.mem.indexOf(u8, content, "ATOMIC_VAR_INIT")) |_| return true;
    }
    return false;
}

test "secure_getenv usage detection returns false for non-existent dir" {
    try std.testing.expect(!scanForSecureGetenvUsage(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "ATOMIC_VAR_INIT usage detection returns false for non-existent dir" {
    try std.testing.expect(!scanForAtomicVarInitUsage(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "endian header detection returns false for non-existent dir" {
    try std.testing.expect(!scanForEndianHeaderUsage(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "asm keyword detection returns false for non-existent dir" {
    try std.testing.expect(!scanForAsmKeyword(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "angle bracket local include detection returns false for non-existent dir" {
    try std.testing.expect(!scanForAngleBracketLocalIncludes(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "angle bracket include dir discovery returns empty for non-existent dir" {
    var dirs = try discoverAngleBracketIncludeDirs(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9");
    defer dirs.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), dirs.items.len);
}

test "stb assert usage detection returns false for non-existent dir" {
    try std.testing.expect(!scanForStbAssertUsage(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
}

test "shorten 64-to-32 risk detection returns false for non-existent dir" {
    try std.testing.expect(!scanForShorten64To32Risk(.failing, std.testing.allocator, "/nonexistent/path_R2Jqk9"));
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
    try std.testing.expect(isSimdCompatibilityDir("simde"));
    try std.testing.expect(isSimdCompatibilityDir("xsimd"));
    try std.testing.expect(!isSimdBridgeDir("zstd"));
    try std.testing.expect(!isSimdBridgeDir("Vulkan-Headers"));
    try std.testing.expect(!isSimdBridgeDir("capstone"));
    try std.testing.expect(pathContainsSimdBridgeDir("/tmp/third_party/AvxToNeon"));
    try std.testing.expect(!pathContainsSimdBridgeDir("/tmp/third_party/simde"));
    try std.testing.expect(pathContainsSimdCompatibilityDir("/tmp/third_party/simde"));
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
