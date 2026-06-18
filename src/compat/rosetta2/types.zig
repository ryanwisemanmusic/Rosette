const std = @import("std");

pub const TargetKind = enum {
    file,
    app_bundle,

    pub fn label(self: TargetKind) []const u8 {
        return switch (self) {
            .file => "file",
            .app_bundle => "app_bundle",
        };
    }
};

pub const BinaryFormat = enum {
    unknown,
    mach_o,
    elf,
    pe,

    pub fn label(self: BinaryFormat) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .mach_o => "mach_o",
            .elf => "elf",
            .pe => "pe",
        };
    }
};

pub const GuestArch = enum {
    unknown,
    arm64,
    x86_64,
    i386,
    x86,
    universal,

    pub fn label(self: GuestArch) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .arm64 => "arm64",
            .x86_64 => "x86_64",
            .i386 => "i386",
            .x86 => "x86",
            .universal => "universal",
        };
    }
};

pub const Backend = enum {
    rosette_elf,
    rosette_pe,
    rosette_macho,
    apple_rosetta2,
    native,
    unsupported,

    pub fn label(self: Backend) []const u8 {
        return switch (self) {
            .rosette_elf => "rosette_elf",
            .rosette_pe => "rosette_pe",
            .rosette_macho => "rosette_macho",
            .apple_rosetta2 => "apple_rosetta2",
            .native => "native",
            .unsupported => "unsupported",
        };
    }
};

pub const FallbackReason = enum {
    none,
    native_arm64_available,
    rosette_backend_pending,
    rosette_tool_missing,
    apple_rosetta2_disabled,
    forced_baseline,
    unsupported_guest,
    unsupported_container,

    pub fn label(self: FallbackReason) []const u8 {
        return switch (self) {
            .none => "none",
            .native_arm64_available => "native_arm64_available",
            .rosette_backend_pending => "rosette_backend_pending",
            .rosette_tool_missing => "rosette_tool_missing",
            .apple_rosetta2_disabled => "apple_rosetta2_disabled",
            .forced_baseline => "forced_baseline",
            .unsupported_guest => "unsupported_guest",
            .unsupported_container => "unsupported_container",
        };
    }
};

pub const Classification = struct {
    target_kind: TargetKind,
    format: BinaryFormat,
    arch: GuestArch,
    requested_path: []const u8,
    executable_path: []const u8,
    has_arm64: bool = false,
    has_x86_64: bool = false,
    has_i386: bool = false,
    note: []const u8 = "",

    pub fn guestLabel(self: Classification) []const u8 {
        if (self.format == .unknown) return "unknown";
        return self.arch.label();
    }

    pub fn routesThroughAppleRosetta2ByDefault(self: Classification) bool {
        return self.format == .mach_o and self.has_x86_64 and !self.has_arm64;
    }
};

pub const Decision = struct {
    backend: Backend,
    reason: FallbackReason,
    detail: []const u8,
};

pub fn appendClassificationSummary(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    class: Classification,
) !void {
    try out.appendSlice(allocator, "target_kind=");
    try out.appendSlice(allocator, class.target_kind.label());
    try out.appendSlice(allocator, " format=");
    try out.appendSlice(allocator, class.format.label());
    try out.appendSlice(allocator, " arch=");
    try out.appendSlice(allocator, class.arch.label());
    try out.appendSlice(allocator, " arm64=");
    try out.appendSlice(allocator, if (class.has_arm64) "true" else "false");
    try out.appendSlice(allocator, " x86_64=");
    try out.appendSlice(allocator, if (class.has_x86_64) "true" else "false");
    try out.appendSlice(allocator, " i386=");
    try out.appendSlice(allocator, if (class.has_i386) "true" else "false");
}
