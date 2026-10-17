//! Target-neutral names used by the local Xenia ABI package.

pub const Architecture = enum(u8) {
    x86_64,
    ppc64,
    arm64,

    pub fn label(self: Architecture) []const u8 {
        return switch (self) {
            .x86_64 => "x86_64",
            .ppc64 => "ppc64",
            .arm64 => "arm64",
        };
    }
};

pub const Endian = enum(u8) {
    little,
    big,

    pub fn label(self: Endian) []const u8 {
        return switch (self) {
            .little => "little",
            .big => "big",
        };
    }
};

pub const Profile = struct {
    architecture: Architecture,
    host_endian: Endian,
    guest_endian: Endian,
    host_pointer_bits: u8,
    guest_pointer_bits: u8,
    host_nop_bytes: []const u8,
    host_nop_word: u32,
    host_nop_width: u8,

    pub fn label(self: Profile) []const u8 {
        return self.architecture.label();
    }
};
