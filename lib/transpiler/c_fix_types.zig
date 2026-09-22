const std = @import("std");

pub const Edit = struct {
    start: usize,
    end: usize,
    replacement: []const u8,
};

pub const FixResult = struct {
    edits: std.ArrayList(Edit),
    warning: bool,

    pub fn deinit(self: *FixResult, allocator: std.mem.Allocator) void {
        for (self.edits.items) |edit| {
            allocator.free(edit.replacement);
        }
        self.edits.deinit(allocator);
    }
};

pub const CppOptions = struct {
    /// Convert `(T)x` to `static_cast`/`reinterpret_cast`, and rewrite
    /// undefined `reinterpret_cast` forms.
    ///
    /// **Off by default, and it must stay off until the pass can tell a cast
    /// from a type.** Its test for "this parenthesised group is a cast" is
    /// positional, and C++ puts parenthesised type lists in places that are not
    /// casts: `int (*)(DIR*)` is a function-pointer declarator and
    /// `std::function<void(void*)>` is a template argument. It rewrote both,
    /// producing `int (*)reinterpret_cast<DIR*>(>)` and
    /// `std::function<voidreinterpret_cast<void*>(> callback)`, and stopped the
    /// tree compiling. The compiler wrapper edits sources in place, so a bad
    /// rewrite is not a failed build — it is a damaged working tree.
    ///
    /// The pass and its tests are kept because the transformation is wanted;
    /// what is missing is a sound predicate for whether a `(` opens a cast.
    cast_rewrites: bool = false,
};

pub const Line = struct {
    start: usize,
    end: usize,
    next: usize,
    text: []const u8,
};
