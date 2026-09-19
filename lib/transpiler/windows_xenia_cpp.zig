//! Opt-in Clang/MinGW ABI adaptation. This does NOT run the general C repair
//! passes over C++, alter an upstream file, or disable any diagnostic.
//! Rules name source paths and exact token sequences; upstream drift stays
//! unchanged and visible. The caller can expose the result through Clang VFS.
const std = @import("std");
const tokenizer = @import("c_tokenizer.zig");
const c_fix = @import("c_fix.zig");

pub const files = [_][]const u8{
    "third_party/microprofile/microprofile.h",
    "src/xenia/base/threading_win.cc",
    "src/xenia/ui/windowed_app_context_win.cc",
    "src/xenia/hid/xinput/xinput_input_driver.cc",
    "src/xenia/ui/windowed_app_main_win.cc",
    "src/xenia/base/main_init_win.cc",
    "src/xenia/gpu/command_processor.h",
    "src/xenia/gpu/draw_util.cc",
    "src/xenia/base/platform_win.h",
};

fn tokens(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(tokenizer.Token) {
    var result: std.ArrayList(tokenizer.Token) = .empty;
    errdefer result.deinit(allocator);
    var scanner = tokenizer.Tokenizer.init(source);
    while (true) {
        const token = scanner.next();
        if (token.kind == .eof) break;
        try result.append(allocator, token);
    }
    return result;
}

fn rule(allocator: std.mem.Allocator, source: []const u8, input: []const tokenizer.Token, result: *c_fix.FixResult, pattern: []const u8, replacement: []const u8) !void {
    var wanted = try tokens(allocator, pattern);
    defer wanted.deinit(allocator);
    if (wanted.items.len == 0 or wanted.items.len > input.len) return;
    for (0..input.len - wanted.items.len + 1) |start| {
        const candidate = input[start..][0..wanted.items.len];
        for (candidate, wanted.items) |actual, expected| {
            if (actual.kind != expected.kind or !std.mem.eql(u8, source[actual.start..actual.end], pattern[expected.start..expected.end])) break;
        } else {
            try result.edits.append(allocator, .{
                .start = candidate[0].start,
                .end = candidate[candidate.len - 1].end,
                .replacement = try allocator.dupe(u8, replacement),
            });
        }
    }
}

pub fn fix(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !c_fix.FixResult {
    var result = c_fix.FixResult{ .edits = .empty, .warning = false };
    errdefer result.deinit(allocator);
    var input = try tokens(allocator, source);
    defer input.deinit(allocator);
    if (std.mem.eql(u8, path, files[0])) {
        // time_t is signed 64-bit on Windows; long is only 32-bit (LLP64).
        try rule(allocator, source, input.items, &result, "MicroProfilePrintf(CB, Handle, \"var DumpUtcCaptureTime = %ld;\\n\", CaptureTime);", "MicroProfilePrintf(CB, Handle, \"var DumpUtcCaptureTime = %lld;\\n\", static_cast<long long>(CaptureTime));");
    } else if (std.mem.eql(u8, path, files[1])) {
        // A by-value C++ object has an address; this guard cannot detect
        // invalid inputs. Preserve both real set_name calls, including empty names.
        try rule(allocator, source, input.items, &result, "void set_name(std::string name) override { if (&name == nullptr) { return; }", "void set_name(std::string name) override {");
    } else if (std.mem.eql(u8, path, files[2])) {
        const fields = [_][]const u8{
            "per_monitor_dpi_v1_api_.get_dpi_for_monitor",
            "per_monitor_dpi_v2_api_.adjust_window_rect_ex_for_dpi",
            "per_monitor_dpi_v2_api_.enable_non_client_dpi_scaling",
            "per_monitor_dpi_v2_api_.get_dpi_for_system",
            "per_monitor_dpi_v2_api_.get_dpi_for_window",
        };
        const exports = [_][]const u8{ "GetDpiForMonitor", "AdjustWindowRectExForDpi", "EnableNonClientDpiScaling", "GetDpiForSystem", "GetDpiForWindow" };
        for (fields, exports, 0..) |field, exported, i| {
            const module = if (i == 0) "shcore_module_" else "user32_module_";
            const pattern = try std.fmt.allocPrint(allocator, "*reinterpret_cast<void**>(&{s}) = GetProcAddress({s}, \"{s}\")", .{ field, module, exported });
            defer allocator.free(pattern);
            const replacement = try std.fmt.allocPrint(allocator, "{s} = reinterpret_cast<decltype({s})>(GetProcAddress({s}, \"{s}\"))", .{ field, field, module, exported });
            defer allocator.free(replacement);
            // Use the actual function-pointer type; no void** aliasing store.
            try rule(allocator, source, input.items, &result, pattern, replacement);
        }
    } else if (std.mem.eql(u8, path, files[3])) {
        const fields = [_][]const u8{ "XInputGetCapabilities_", "XInputGetState_", "XInputGetStateEx_", "XInputGetKeystroke_", "XInputSetState_", "XInputEnable_" };
        const locals = [_][]const u8{ "xigc", "xigs", "xigsEx", "xigk", "xiss", "xie" };
        for (fields, locals) |field, local| {
            const pattern = try std.fmt.allocPrint(allocator, "{s} = {s};", .{ field, local });
            defer allocator.free(pattern);
            const replacement = try std.fmt.allocPrint(allocator, "{s} = reinterpret_cast<void*>({s});", .{ field, local });
            defer allocator.free(replacement);
            // The upstream members intentionally store opaque addresses;
            // preserve that ABI and their subsequent typed invocation casts.
            try rule(allocator, source, input.items, &result, pattern, replacement);
        }
    } else if (std.mem.eql(u8, path, files[4])) {
        try rule(allocator, source, input.items, &result, "*reinterpret_cast<unsigned short*>(base) == 'ZM'", "*reinterpret_cast<unsigned short*>(base) == 0x5a4d");
    } else if (std.mem.eql(u8, path, files[5])) {
        // GNU COFF honors init_priority through its ordered constructor
        // sections. Keep the CPU check before default-priority constructors.
        try rule(allocator, source, input.items, &result, "#pragma init_seg(lib)", "/* Rosette: GNU COFF init_priority on the CPU feature checker below. */");
        try rule(allocator, source, input.items, &result, "static StartupCpuFeatureCheck gStartupAvxCheck;", "static StartupCpuFeatureCheck gStartupAvxCheck __attribute__((init_priority(101)));");
        // A partial match must not remove init_seg without replacing its
        // initialization ordering. Let the compiler expose upstream drift.
        if (result.edits.items.len != 2) {
            result.deinit(allocator);
            result = .{ .edits = .empty, .warning = false };
        }
    } else if (std.mem.eql(u8, path, files[6])) {
        // These two virtual bodies live in command_processor.cc. Declaring
        // them inline in unrelated translation units requires unavailable
        // definitions. Do not remove inline from other header-defined functions.
        try rule(allocator, source, input.items, &result, "XE_FORCEINLINE virtual void WriteRegistersFromMem(uint32_t start_index, uint32_t* base, uint32_t num_registers);", "virtual void WriteRegistersFromMem(uint32_t start_index, uint32_t* base, uint32_t num_registers);");
        try rule(allocator, source, input.items, &result, "XE_FORCEINLINE virtual void WriteRegisterRangeFromRing(xe::RingBuffer* ring, uint32_t base, uint32_t num_registers);", "virtual void WriteRegisterRangeFromRing(xe::RingBuffer* ring, uint32_t base, uint32_t num_registers);");
    } else if (std.mem.eql(u8, path, files[7])) {
        // Attach the size policy to the intended function, not an unsupported
        // MSVC pragma or a translation-unit-wide optimization downgrade.
        try rule(allocator, source, input.items, &result, "XE_MSVC_OPTIMIZE_SMALL() bool GetResolveInfo", "__attribute__((minsize)) bool GetResolveInfo");
        try rule(allocator, source, input.items, &result, "XE_MSVC_OPTIMIZE_REVERT()", "/* Rosette: minsize was function-local. */");
    } else if (std.mem.eql(u8, path, files[8])) {
        // MinGW's real SDK filename is lowercase. A case alias alone can
        // lose to Clang's cached SDK include after windows.h was consumed.
        try rule(allocator, source, input.items, &result, "#include <ObjBase.h>", "#include <objbase.h>");
    }
    return result;
}

fn expectFix(path: []const u8, source: []const u8, expected: []const u8, count: usize) !void {
    const allocator = std.testing.allocator;
    var result = try fix(allocator, path, source);
    defer result.deinit(allocator);
    try std.testing.expectEqual(count, result.edits.items.len);
    const output = try c_fix.applyEdits(allocator, source, result.edits.items);
    defer allocator.free(output);
    try std.testing.expectEqualStrings(expected, output);
    var twice = try fix(allocator, path, output);
    defer twice.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), twice.edits.items.len);
}

test "LLP64 formatting keeps full-width time rather than truncating it to long" {
    try expectFix(files[0], "MicroProfilePrintf(CB, Handle, \"var DumpUtcCaptureTime = %ld;\\n\", CaptureTime);", "MicroProfilePrintf(CB, Handle, \"var DumpUtcCaptureTime = %lld;\\n\", static_cast<long long>(CaptureTime));", 1);
}

test "token rules don't modify comments, string contents or unrelated paths" {
    const text = "// *reinterpret_cast<unsigned short*>(base) == 'ZM'\nconst char* s = \"*reinterpret_cast<unsigned short*>(base) == 'ZM'\";";
    try expectFix(files[4], text, text, 0);
    try expectFix("unrelated.cc", "XInputEnable_ = xie;", "XInputEnable_ = xie;", 0);
    try expectFix(files[1], "void set_name(std::string* name) override { if (name == nullptr) { return; } }", "void set_name(std::string* name) override { if (name == nullptr) { return; } }", 0);
}

test "typed function assignment retains the availability check and function type" {
    try expectFix(files[2], "(*reinterpret_cast<void**>(&per_monitor_dpi_v2_api_.get_dpi_for_window) = GetProcAddress(user32_module_, \"GetDpiForWindow\")) != nullptr;", "(per_monitor_dpi_v2_api_.get_dpi_for_window = reinterpret_cast<decltype(per_monitor_dpi_v2_api_.get_dpi_for_window)>(GetProcAddress(user32_module_, \"GetDpiForWindow\"))) != nullptr;", 1);
    try expectFix(files[3], "XInputEnable_ = xie;", "XInputEnable_ = reinterpret_cast<void*>(xie);", 1);
}

test "header defined inline bodies and other optimization scopes stay untouched" {
    const input = "XE_FORCEINLINE virtual void AnotherMethod(); XE_FORCEINLINE int header_body() { return 1; }";
    try expectFix(files[6], input, input, 0);
    try expectFix(files[7], "XE_MSVC_OPTIMIZE_SMALL() bool GetResolveInfo() { return true; } XE_MSVC_OPTIMIZE_REVERT()", "__attribute__((minsize)) bool GetResolveInfo() { return true; } /* Rosette: minsize was function-local. */", 2);
}

test "constructor priority and DOS magic are explicit for GNU Windows COFF" {
    try expectFix(files[5], "#pragma init_seg(lib)\nstatic StartupCpuFeatureCheck gStartupAvxCheck;", "/* Rosette: GNU COFF init_priority on the CPU feature checker below. */\nstatic StartupCpuFeatureCheck gStartupAvxCheck __attribute__((init_priority(101)));", 2);
    try expectFix(files[4], "*reinterpret_cast<unsigned short*>(base) == 'ZM'", "*reinterpret_cast<unsigned short*>(base) == 0x5a4d", 1);
    try expectFix(files[1], "void set_name(std::string name) override { if (&name == nullptr) { return; } do_set_name(name); }", "void set_name(std::string name) override { do_set_name(name); }", 1);
}

test "SDK header case is corrected without changing unrelated include names" {
    try expectFix(files[8], "#include <ObjBase.h>\n#include <ObjOther.h>", "#include <objbase.h>\n#include <ObjOther.h>", 1);
}

test "constructor adaptation is atomic across the pragma and its checker" {
    const drift = "#pragma init_seg(lib)\nstatic DifferentCpuChecker gStartupAvxCheck;";
    try expectFix(files[5], drift, drift, 0);
}
