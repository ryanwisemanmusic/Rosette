const std = @import("std");
const c_tokenizer = @import("c_tokenizer.zig");
const types = @import("c_fix_types.zig");
const shared = @import("c_fix_shared.zig");
const c_fix_unused = @import("c_fix_unused.zig");
const c_fix_includes = @import("c_fix_includes.zig");
const c_fix_casts = @import("c_fix_casts.zig");
const c_fix_syntax = @import("c_fix_syntax.zig");

const Token = c_tokenizer.Token;
const Tokenizer = c_tokenizer.Tokenizer;

pub const Edit = types.Edit;
pub const FixResult = types.FixResult;
pub const CppOptions = types.CppOptions;

const isCompoundType = shared.isCompoundType;
const isIdentifierToken = shared.isIdentifierToken;
const isLikelyPointerReturningFunction = shared.isLikelyPointerReturningFunction;
const isNarrowTypedefName = shared.isNarrowTypedefName;
const isPointerSubtraction = shared.isPointerSubtraction;
const isStorageClass = shared.isStorageClass;
const isTypeQualifier = shared.isTypeQualifier;
const isWideExpressionStart = shared.isWideExpressionStart;
const isWideFunctionName = shared.isWideFunctionName;
const skipToSemicolon = shared.skipToSemicolon;
const typeIsNarrow = shared.typeIsNarrow;
const appendBracketAttributeFixes = c_fix_includes.appendBracketAttributeFixes;
const appendConstantConversionCasts = c_fix_casts.appendConstantConversionCasts;
const appendDepoisonFixes = c_fix_includes.appendDepoisonFixes;
const appendDeprecatedDeclReplacement = c_fix_syntax.appendDeprecatedDeclReplacement;
const appendFmtPointerCasts = c_fix_casts.appendFmtPointerCasts;
const appendLocalAngleIncludeQuotes = c_fix_includes.appendLocalAngleIncludeQuotes;
const appendLogicalOpParentheses = c_fix_syntax.appendLogicalOpParentheses;
const appendMissingBraces = c_fix_syntax.appendMissingBraces;
const appendMissingFieldInitializers = c_fix_syntax.appendMissingFieldInitializers;
const appendOldStyleCastConversion = c_fix_casts.appendOldStyleCastConversion;
const appendParenthesesEquality = c_fix_syntax.appendParenthesesEquality;
const appendStaticCastVoidUnwrap = c_fix_casts.appendStaticCastVoidUnwrap;
const appendStrictAliasingTypePuns = c_fix_casts.appendStrictAliasingTypePuns;
const appendSwitchDefaultClauses = c_fix_syntax.appendSwitchDefaultClauses;
const appendTrivialMacIncludeCollapses = c_fix_includes.appendTrivialMacIncludeCollapses;
const appendUndefinedReinterpretCast = c_fix_casts.appendUndefinedReinterpretCast;
const appendUnusedConstAnnotations = c_fix_unused.appendUnusedConstAnnotations;
const appendUnusedLocalAnnotations = c_fix_unused.appendUnusedLocalAnnotations;
const appendUnusedSetLocalAnnotations = c_fix_unused.appendUnusedSetLocalAnnotations;
const appendUnusedVarDeclarations = c_fix_unused.appendUnusedVarDeclarations;
const appendVoidSuppressorElisions = c_fix_unused.appendVoidSuppressorElisions;
const expressionIsCharPointerUnsigned = c_fix_casts.expressionIsCharPointerUnsigned;
const isCharPointerType = c_fix_casts.isCharPointerType;
const isFunctionCall = c_fix_casts.isFunctionCall;

pub fn fixSource(allocator: std.mem.Allocator, source: []const u8) !FixResult {
    return fixSourceWithMode(allocator, source, false);
}

pub fn fixSourceWithMode(allocator: std.mem.Allocator, source: []const u8, cpp_mode: bool) !FixResult {
    return fixSourceWithOptions(allocator, source, cpp_mode, .{});
}

/// What the C++ pipeline is allowed to rewrite.
pub fn fixSourceWithOptions(
    allocator: std.mem.Allocator,
    source: []const u8,
    cpp_mode: bool,
    cpp_options: CppOptions,
) !FixResult {
    var tok = Tokenizer.init(source);
    var all_tokens: std.ArrayList(Token) = .empty;
    defer all_tokens.deinit(allocator);

    while (true) {
        const t = tok.next();
        try all_tokens.append(allocator, t);
        if (t.kind == .eof) break;
    }

    const tokens = all_tokens.items;
    var edits: std.ArrayList(Edit) = .empty;
    errdefer {
        for (edits.items) |e| allocator.free(e.replacement);
        edits.deinit(allocator);
    }
    const warning = false;

    try appendDepoisonFixes(allocator, source, &edits, cpp_mode);
    if (cpp_mode) {
        // A C++ source gets only the rewrites that are themselves C++: the
        // passes below this point produce C, and several of them (the `(int)`
        // return wrap, the unused-variable annotations) would be wrong here.
        //
        // These four used to be unreachable. The early return sat above them,
        // so the block at the end of this function that ran them "if
        // (cpp_mode)" could never execute, and every C++-only rewrite the
        // transpiler implements was dead code.
        try appendStaticCastVoidUnwrap(allocator, source, tokens, &edits);
        try appendFmtPointerCasts(allocator, source, tokens, &edits);
        if (cpp_options.cast_rewrites) {
            try appendOldStyleCastConversion(allocator, source, tokens, &edits);
            try appendUndefinedReinterpretCast(allocator, source, tokens, &edits);
        }
        return .{ .edits = edits, .warning = warning };
    }
    try appendBracketAttributeFixes(allocator, source, tokens, &edits, cpp_mode);
    try appendTrivialMacIncludeCollapses(allocator, source, &edits);
    try appendLocalAngleIncludeQuotes(allocator, source, &edits);
    try appendVoidSuppressorElisions(allocator, source, &edits, cpp_mode);
    try appendStaticCastVoidUnwrap(allocator, source, tokens, &edits);
    try appendFmtPointerCasts(allocator, source, tokens, &edits);
    try appendUnusedLocalAnnotations(allocator, source, &edits, cpp_mode);
    try appendUnusedVarDeclarations(allocator, source, tokens, &edits, cpp_mode);
    try appendUnusedSetLocalAnnotations(allocator, source, &edits, cpp_mode);
    try appendUnusedConstAnnotations(allocator, source, &edits, cpp_mode);
    try appendParenthesesEquality(allocator, source, tokens, &edits);
    try appendSwitchDefaultClauses(allocator, source, tokens, &edits);
    try appendMissingFieldInitializers(allocator, source, tokens, &edits);
    try appendStrictAliasingTypePuns(allocator, source, tokens, &edits);
    try appendMissingBraces(allocator, source, tokens, &edits);
    try appendDeprecatedDeclReplacement(allocator, source, tokens, &edits);
    try appendLogicalOpParentheses(allocator, source, tokens, &edits);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (isStorageClass(tokens[i].kind)) continue;

        if (tokens[i].kind == .keyword_return) {
            if (i + 1 < tokens.len) {
                const next = tokens[i + 1];
                if (next.kind == .keyword_sizeof or isWideFunctionName(next, source) or
                    (next.kind == .identifier and
                        isWideExpressionStart(next, source) and
                        !isLikelyPointerReturningFunction(next, source)))
                {
                    const wrap_start = next.start;
                    const semi = skipToSemicolon(tokens, i + 1);
                    const wrap_end = if (semi < tokens.len) tokens[semi].start else tokens[tokens.len - 1].end;
                    if (wrap_end > wrap_start) {
                        try edits.append(allocator, .{
                            .start = wrap_start,
                            .end = wrap_start,
                            .replacement = try allocator.dupe(u8, "(int)"),
                        });
                    }
                }
            }
            continue;
        }
        if (!isCompoundType(tokens[i].kind) and !isIdentifierToken(tokens[i].kind)) continue;

        if (isIdentifierToken(tokens[i].kind)) {
            const slice = source[tokens[i].start..tokens[i].end];
            if (!std.mem.endsWith(u8, slice, "_t") and
                !isNarrowTypedefName(slice) and
                !isWideFunctionName(tokens[i], source) and
                slice.len > 0 and (slice[0] < 'A' or slice[0] > 'Z'))
            {
                continue;
            }
        }

        var type_end = i + 1;
        while (type_end < tokens.len and
            (isCompoundType(tokens[type_end].kind) or
                isTypeQualifier(tokens[type_end].kind) or
                tokens[type_end].kind == .star))
        {
            type_end += 1;
        }

        if (type_end >= tokens.len) continue;

        const has_ptr = type_end > i and tokens[type_end - 1].kind == .star;
        const name_pos = type_end;

        if (!isIdentifierToken(tokens[name_pos].kind)) continue;

        const name = tokens[name_pos];
        _ = name;

        if (name_pos + 1 < tokens.len and tokens[name_pos + 1].kind == .eq) {
            const eq_pos = name_pos + 1;
            if (eq_pos + 1 >= tokens.len) continue;

            const rhs_start = eq_pos + 1;
            const rhs = tokens[rhs_start];

            if (has_ptr) {
                if (isCharPointerType(tokens, i)) |lhs_unsigned| {
                    var need_cast = false;
                    if (rhs.kind == .string_literal and lhs_unsigned) {
                        need_cast = true;
                    } else if (rhs.kind == .identifier) {
                        if (expressionIsCharPointerUnsigned(tokens, rhs_start, source)) |rhs_unsigned| {
                            if (lhs_unsigned != rhs_unsigned) need_cast = true;
                        }
                    }
                    if (need_cast) {
                        const cast_text = if (lhs_unsigned) "(unsigned char *)" else "(char *)";
                        try edits.append(allocator, .{
                            .start = rhs.start,
                            .end = rhs.start,
                            .replacement = try allocator.dupe(u8, cast_text),
                        });
                    }
                }
                continue;
            }

            if (!typeIsNarrow(tokens, i, source)) continue;

            try appendConstantConversionCasts(allocator, source, tokens, i, type_end, rhs_start, &edits);

            if (rhs.kind == .keyword_sizeof or isWideExpressionStart(rhs, source)) {
                const cast_type = source[tokens[i].start..tokens[type_end - 1].end];

                try edits.append(allocator, .{
                    .start = rhs.start,
                    .end = rhs.start,
                    .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
                });
            } else if (isPointerSubtraction(tokens, rhs_start)) {
                const cast_type = source[tokens[i].start..tokens[type_end - 1].end];
                try edits.append(allocator, .{
                    .start = rhs.start,
                    .end = rhs.start,
                    .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
                });
            } else if (isFunctionCall(tokens, rhs_start)) {
                const cast_type = source[tokens[i].start..tokens[type_end - 1].end];
                try edits.append(allocator, .{
                    .start = rhs.start,
                    .end = rhs.start,
                    .replacement = try std.fmt.allocPrint(allocator, "({s})", .{cast_type}),
                });
            }
        }
    }

    return .{ .edits = edits, .warning = warning };
}

pub fn applyEdits(allocator: std.mem.Allocator, source: []const u8, edits: []const Edit) ![]u8 {
    if (edits.len == 0) return try allocator.dupe(u8, source);

    const sorted = try allocator.alloc(Edit, edits.len);
    defer allocator.free(sorted);
    @memcpy(sorted, edits);

    std.mem.sort(Edit, sorted, {}, struct {
        fn lessThan(_: void, a: Edit, b: Edit) bool {
            return a.start > b.start;
        }
    }.lessThan);

    var result = try allocator.dupe(u8, source);
    for (sorted) |edit| {
        const prefix = result[0..edit.start];
        const suffix = result[edit.end..];
        var new_result: std.ArrayList(u8) = .empty;
        defer new_result.deinit(allocator);
        try new_result.appendSlice(allocator, prefix);
        try new_result.appendSlice(allocator, edit.replacement);
        try new_result.appendSlice(allocator, suffix);
        allocator.free(result);
        result = try new_result.toOwnedSlice(allocator);
    }

    return result;
}

test "fix strlen assigned to int" {
    const src = "int x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.edits.items.len);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("int x = (int)strlen(s);", output);
}

test "fix sizeof assigned to int32_t" {
    const src = "int32_t x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(int32_t)") != null);
}

test "fix strlen assigned to Windows-style UINT4" {
    const src = "UINT4 x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("UINT4 x = (UINT4)strlen(s);", output);
}

test "fix sizeof assigned to GLib guint" {
    const src = "guint x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("guint x = (guint)sizeof(buf);", output);
}

test "fix return strlen" {
    const src = "return strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
}

test "fix return sizeof" {
    const src = "return sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
}

test "no false positive on pointer allocation with size in its name" {
    const src =
        "AVMasteringDisplayMetadata *f(void) { " ++
        "return av_mastering_display_metadata_alloc_size(NULL); " ++
        "}";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "no false positive on size_t assignment" {
    const src = "size_t x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "fix sizeof in for-loop init" {
    const src = "int32_t x = sizeof(buf);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(int32_t)") != null);
}

test "no edit for uint64_t" {
    const src = "uint64_t x = strlen(s);";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "collapse trivial mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/base/math_mac.h"
        \\#else
        \\#include "xenia/base/math.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("#include \"xenia/base/math.h\"\n", output);
}

test "collapse duplicate canonical trivial mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/base/math.h"
        \\#else
        \\#include "xenia/base/math.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("#include \"xenia/base/math.h\"\n", output);
}

test "quote vendored angle include" {
    const src =
        \\#include <llvm/ADT/BitVector.h>
        \\#include <vector>
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(
        "#include \"llvm/ADT/BitVector.h\"\n#include <vector>\n",
        output,
    );
}

test "annotate unused single line local declaration" {
    const src =
        \\void f() {
        \\  auto arena = builder->arena();
        \\  use(builder);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ auto arena") != null);
}

test "do not annotate used local declaration" {
    const src =
        \\void f() {
        \\  uint32_t index_buffer_base = regs[0];
        \\  use(index_buffer_base);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "[[maybe_unused]]") == null);
}

test "local used only in non-apple branch gets maybe_unused annotation" {
    const src =
        \\void f() {
        \\  int x = 0;
        \\#ifndef __APPLE__
        \\  use(x);
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x") != null);
}

test "local used in apple branch gets no maybe_unused annotation" {
    const src =
        \\void f() {
        \\  int x = 0;
        \\#ifdef __APPLE__
        \\  use(x);
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "[[maybe_unused]]") == null);
}

test "do not collapse real mac include conditional" {
    const src =
        \\#if XE_PLATFORM_MACOS
        \\#include "xenia/kernel/kernel_state_mac.h"
        \\#else
        \\#include "xenia/kernel/kernel_state.h"
        \\#endif
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "unused but set local gets maybe_unused annotation" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = 42;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)x") == null);
}

test "standalone void suppressor becomes maybe_unused local annotation" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  (void)x;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ int x;") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)x") == null);
}

test "apple-only void suppressor block becomes maybe_unused parameter annotation" {
    const src =
        \\void f(int dfn) {
        \\#ifdef __APPLE__
        \\  (void)dfn;
        \\#endif
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "void f(/* rosette-c-fix: maybe_unused */ int dfn)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(void)dfn") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "#ifdef __APPLE__") == null);
}

test "static_cast void expression keeps side effects without suppressor cast" {
    const src =
        \\void f(void) {
        \\  static_cast<void>(call());
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "call();") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void>") == null);
}

test "static_cast void macro continuation keeps expression" {
    const src =
        \\#define LOAD_KERNEL_MODULE(t) \
        \\  static_cast<void>(kernel_state_->LoadKernelModule<kernel::t>())
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "kernel_state_->LoadKernelModule<kernel::t>()") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void>") == null);
}

test "fmt logging pointer cast becomes fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XELOGI("Object pointer: {}", static_cast<void*>(object));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "fmt::ptr(object)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<void*>") == null);
}

test "fmt logging const pointer cast becomes fmt ptr" {
    const src =
        \\void f(const Device* device) {
        \\  XELOGI("Device pointer: {}", static_cast<const void*>(device));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "fmt::ptr(device)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<const void*>") == null);
}

test "printf style pointer cast is not fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XBDM_TRACE("Object pointer: %p\n", static_cast<void*>(object));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "nested non-format pointer cast is not fmt ptr" {
    const src =
        \\void f(Object* object) {
        \\  XELOGI("Object pointer: {}", wrap(static_cast<void*>(object)));
        \\}
        \\
    ;
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "unused but set local used on RHS gets no suppression" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = x + 1;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "used variable after assignment gets no unused-set suppression" {
    const src =
        \\void f(void) {
        \\  int x;
        \\  x = 42;
        \\  use(x);
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "sign-conversion cast for function call RHS" {
    const src = "uint32_t x = getchar();";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(uint32_t)") != null);
}

test "pointer-sign cast unsigned char* from string literal" {
    const src = "unsigned char *p = \"hello\";";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(unsigned char *)") != null);
}

test "no pointer-sign cast for already-correct pointer" {
    const src = "char *p = \"hello\";";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "parentheses-equality wraps if assignment" {
    const src = "if (x = y) { f(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("if ((x = y)) { f(); }", output);
}

test "parentheses-equality wraps while assignment" {
    const src = "while (x = next()) { process(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "((x = next()))") != null);
}

test "no parentheses-equality for comparison" {
    const src = "if (x == y) { f(); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "no parentheses-equality for for-loop init" {
    const src = "for (i = 0; i < n; i++) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "constant-conversion cast negative literal to unsigned" {
    const src = "uint32_t x = -1;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "(uint32_t)") != null);
}

test "switch default clause inserted when missing" {
    const src =
        \\switch (x) {
        \\  case 1: break;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "default: break;") != null);
}

test "switch no default when default already present" {
    const src =
        \\switch (x) {
        \\  case 1: break;
        \\  default: break;
        \\}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "unused file-scope const gets maybe_unused" {
    const src =
        \\const int FOO = 42;
        \\void f(void) {}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ const int FOO") != null);
}

test "used file-scope const gets no annotation" {
    const src =
        \\const int BAR = 42;
        \\int f(void) { return BAR; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "static const at file scope gets maybe_unused" {
    const src =
        \\static const int BAZ = 42;
        \\void f(void) {}
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "/* rosette-c-fix: maybe_unused */ static const int BAZ") != null);
}

test "extern const at file scope skipped" {
    const src =
        \\extern const int QUX;
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "struct partial initializer gets padded" {
    const src =
        \\struct Foo { int a; int b; int c; };
        \\void f(void) { struct Foo x = {1, 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, ", 0") != null);
}

test "struct full initializer unchanged" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo f(void) { return (struct Foo){1, 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "struct designated initializer skipped" {
    const src =
        \\struct Foo { int a; int b; int c; };
        \\struct Foo f(void) { return (struct Foo){.a = 1, .b = 2}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "typedef struct partial initializer gets padded" {
    const src =
        \\typedef struct { int a; int b; int c; } Foo;
        \\void f(void) { Foo x = {1}; }
        \\
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, ", 0") != null);
}

test "strict-aliasing read pun via memcpy" {
    const src = "uint32_t x = *(uint32_t *)&f;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "memcpy") != null);
}

test "strict-aliasing write pun via memcpy" {
    const src = "*(uint32_t *)&f = 0x3f800000;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.edits.items.len > 0);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "memcpy") != null);
}

test "strict-aliasing no match without cast" {
    const src = "int x = *p;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "logical-op-parentheses wraps && before ||" {
    const src = "if (a && b || c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "&& b") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "|| c") != null);
}

test "logical-op-parentheses wraps && after ||" {
    const src = "if (a || b && c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "&& c") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "a || ") != null);
}

test "logical-op-parentheses no wrap on single operator" {
    const src = "if (a && b) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "logical-op-parentheses no wrap when already parenthesised" {
    const src = "if ((a && b) || c) { }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast int to float in cpp mode" {
    const src = "double x = (double)42;";
    var result = try fixSourceWithOptions(std.testing.allocator, src, true, .{ .cast_rewrites = true });
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "static_cast<double>") != null);
}

test "old-style-cast pointer cast in cpp mode" {
    const src = "void *p = (uint32_t *)ptr;";
    var result = try fixSourceWithOptions(std.testing.allocator, src, true, .{ .cast_rewrites = true });
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "reinterpret_cast<uint32_t *>") != null);
}

test "old-style-cast does not run in C mode" {
    const src = "double x = (double)42;";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast does not touch function call parens" {
    const src = "void f(void) { }";
    var result = try fixSourceWithMode(std.testing.allocator, src, true);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "old-style-cast conversion leaves function pointer types alone" {
    // The declarator that broke a real build: the parenthesised `(DIR*)` here
    // is the parameter list of a function-pointer type, and the `(` before it
    // closes `(*)`. Nothing whose opening parenthesis follows a closing bracket
    // is a cast.
    const src =
        \\using DirHandle = std::unique_ptr<DIR, int (*)(DIR*)>;
        \\void g(void) {
        \\  int (*fn)(int) = nullptr;
        \\  (*fn)(3);
        \\}
        \\
    ;
    var result = try fixSourceWithOptions(std.testing.allocator, src, true, .{ .cast_rewrites = true });
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "int (*)(DIR*)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "reinterpret_cast<DIR*>") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "int (*fn)(int)") != null);
}

test "old-style-cast struct keyword cast" {
    const src = "struct Foo *p = (struct Foo *)ptr;";
    var result = try fixSourceWithOptions(std.testing.allocator, src, true, .{ .cast_rewrites = true });
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "reinterpret_cast<struct Foo *>") != null);
}

test "missing-braces insert inner braces for array of struct" {
    const src =
        \\struct Foo { int a; int b; };
        \\void f(void) { struct Foo arr[2] = { 1, 2, 3, 4 }; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "{{ 1, 2}") != null);
}

test "missing-braces no change when already braced" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo* f(void) { static struct Foo arr[2] = { {1, 2}, {3, 4} }; return arr; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "missing-braces no change for non-array struct" {
    const src =
        \\struct Foo { int a; int b; };
        \\struct Foo f(void) { return (struct Foo){ 1, 2 }; }
    ;
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}

test "deprecated sprintf replaced with snprintf" {
    const src = "void f(void) { sprintf(buf, \"%d\", x); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "snprintf") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(buf)") != null);
}

test "deprecated strcpy replaced with strlcpy" {
    const src = "void f(void) { strcpy(dst, src); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "strlcpy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(dst)") != null);
}

test "deprecated strcat replaced with strlcat" {
    const src = "void f(void) { strcat(dst, src); }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    const output = try applyEdits(std.testing.allocator, src, result.edits.items);
    defer std.testing.allocator.free(output);
    try std.testing.expect(result.edits.items.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "strlcat") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "sizeof(dst)") != null);
}

test "deprecated no false positive on unrelated sprintf-like" {
    const src = "int f(void) { int foo_sprintf = 42; return foo_sprintf; }";
    var result = try fixSource(std.testing.allocator, src);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.edits.items.len);
}
