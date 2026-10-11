//! Which native Vulkan driver is drawing the guest's frames.
//!
//! Before 2026-10-04 the run log could not say: the adapter name is the GPU's
//! ("Apple M2 Max") for every Metal-backed driver, and this Mac has three
//! installed (MoltenVK 1.2.7 from the January 2024 SDK, MoltenVK 1.4.1 from
//! SDK 1.4.341, KosmicKrisp). Which one answers depends on `VULKAN_SDK`,
//! `VK_ICD_FILENAMES` and `VK_DRIVER_FILES` in the launching shell, so two
//! runs of the same build can render on different drivers. This decodes
//! `VkPhysicalDeviceDriverProperties` so every log names the driver.
const std = @import("std");
const abi = @import("abi.zig");

pub const ApiVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn decode(raw: u32) ApiVersion {
        return .{ .major = (raw >> 22) & 0x7F, .minor = (raw >> 12) & 0x3FF, .patch = raw & 0xFFF };
    }
};

/// `VkDriverId` names, for the drivers a Mac can plausibly load.
pub fn driverIdName(id: u32) ?[]const u8 {
    return switch (id) {
        3 => "MESA_RADV",
        10 => "GOOGLE_SWIFTSHADER",
        13 => "MESA_LLVMPIPE",
        14 => "MOLTENVK",
        22 => "MESA_VENUS",
        24 => "MESA_NVK",
        26 => "MESA_HONEYKRISP",
        else => null,
    };
}

pub const Identity = struct {
    driver_id: u32 = 0,
    name_storage: [256]u8 = [_]u8{0} ** 256,
    info_storage: [256]u8 = [_]u8{0} ** 256,
    conformance: abi.ConformanceVersion = .{},
    api: ApiVersion = .{ .major = 0, .minor = 0, .patch = 0 },
    known: bool = false,

    pub fn fromProperties(properties: *const abi.PhysicalDeviceDriverProperties, api_version: u32) Identity {
        var identity = Identity{
            .driver_id = properties.driver_id,
            .conformance = properties.conformance_version,
            .api = ApiVersion.decode(api_version),
            .known = true,
        };
        @memcpy(&identity.name_storage, &properties.driver_name);
        @memcpy(&identity.info_storage, &properties.driver_info);
        identity.name_storage[identity.name_storage.len - 1] = 0;
        identity.info_storage[identity.info_storage.len - 1] = 0;
        return identity;
    }

    pub fn name(self: *const Identity) []const u8 {
        return cString(&self.name_storage);
    }

    pub fn info(self: *const Identity) []const u8 {
        return cString(&self.info_storage);
    }

    pub fn isMoltenVK(self: *const Identity) bool {
        return self.driver_id == 14 or std.mem.eql(u8, self.name(), "MoltenVK");
    }
};

pub fn cString(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..end];
}

test "the driver identity names MoltenVK 1.2.7 on a Vulkan 1.2.275 device" {
    var properties = abi.PhysicalDeviceDriverProperties{ .driver_id = 14 };
    @memcpy(properties.driver_name[0..8], "MoltenVK");
    @memcpy(properties.driver_info[0..5], "1.2.7");
    // The 2026-10-04 run's adapter line: api=0x402113.
    const identity = Identity.fromProperties(&properties, 0x402113);
    try std.testing.expectEqualStrings("MoltenVK", identity.name());
    try std.testing.expectEqualStrings("1.2.7", identity.info());
    try std.testing.expect(identity.isMoltenVK());
    try std.testing.expectEqual(@as(u32, 1), identity.api.major);
    try std.testing.expectEqual(@as(u32, 2), identity.api.minor);
    try std.testing.expectEqual(@as(u32, 275), identity.api.patch);
    try std.testing.expectEqualStrings("MOLTENVK", driverIdName(identity.driver_id).?);
    try std.testing.expect(driverIdName(9999) == null);
}

test "an unterminated driver string stays inside its storage" {
    var properties = abi.PhysicalDeviceDriverProperties{};
    @memset(&properties.driver_name, 'x');
    const identity = Identity.fromProperties(&properties, 0);
    try std.testing.expectEqual(@as(usize, 255), identity.name().len);
}
