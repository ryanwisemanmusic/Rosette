const std = @import("std");

/// Kind of parsed PowerShell (.ps1) line.
pub const CommandType = enum {
    comment,
    variable,
    if_not_path,
    if_path,
    block_end,
    command,
};

/// One parsed .ps1 line.  Slice fields point either into the original
/// source text or into translator-owned allocations (freed by
/// `Ps1Translator.deinit`).
pub const Ps1Command = struct {
    kind: CommandType,
    /// Original raw line (may include leading/trailing whitespace).
    raw: []const u8,
    /// Comment text (for `.comment`).
    text: []const u8 = "",
    /// Variable name without the leading `$` (for `.variable`).
    name: []const u8 = "",
    /// Variable value (for `.variable`).
    value: []const u8 = "",
    /// Test-Path argument (for `.if_not_path` / `.if_path`).
    path: []const u8 = "",
    /// Inline body after the opening brace (for `.if_not_path` / `.if_path`).
    body: []const u8 = "",
    /// Command word (for `.command`).
    command: []const u8 = "",
    /// Everything after the command word, untrimmed (for `.command`).
    args: []const u8 = "",
};

/// Error set for .ps1 parsing, translation, and execution.
pub const Ps1Error = error{
    FileNotFound,
    ReadError,
    InvalidUtf8,
    OutOfMemory,
    ExecutionFailed,
};

test {
    std.testing.refAllDecls(@This());
}
