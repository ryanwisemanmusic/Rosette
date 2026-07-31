const std = @import("std");

/// I/O redirect extracted from a .bat command line.
pub const Redirect = struct {
    /// ">>" (append) or ">" (overwrite).
    op: []const u8,
    /// Target file path.
    file: []const u8,
};

/// Kind of parsed .bat line.
pub const CommandKind = enum {
    label,
    comment,
    command,
};

/// One parsed .bat line. All string slices point into the original source.
pub const BatCommand = struct {
    kind: CommandKind,
    /// Original raw line (may include leading/trailing whitespace).
    raw: []const u8,
    /// True when the line started with '@'.
    suppress: bool = false,
    /// Lowercased command word (e.g. "echo", "del", "if").
    command: []const u8 = "",
    /// Everything after the command word, untrimmed.
    args: []const u8 = "",
    /// Extracted redirect, if any.
    redirect: ?Redirect = null,
    /// For labels: the label name (without the leading colon).
    label_name: []const u8 = "",
    /// For comments: the comment text.
    comment_text: []const u8 = "",
};

/// Error set for .bat parsing, translation, and execution.
pub const BatError = error{
    FileNotFound,
    ReadError,
    InvalidUtf8,
    OutOfMemory,
    ExecutionFailed,
};
