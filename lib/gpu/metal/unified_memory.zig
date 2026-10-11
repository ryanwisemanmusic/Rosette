//! Resource-storage policy for Apple Silicon's shared physical memory.
//!
//! Unified physical memory does not make every Metal resource CPU-visible or
//! make `shared` storage universally fastest. Frequently CPU-updated buffers
//! and readback surfaces benefit from shared access; GPU-only textures and
//! transient attachments should retain private storage when available. This
//! module states that policy without silently changing MoltenVK allocations.

const std = @import("std");

pub const StorageMode = enum {
    shared,
    managed,
    private,
};

pub const ResourceUse = enum {
    cpu_stream_write,
    cpu_readback,
    gpu_sampled_texture,
    gpu_storage_texture,
    gpu_transient_attachment,
};

pub const Device = struct {
    unified_memory: bool,
    shared_supported: bool,
    managed_supported: bool,
    private_supported: bool,
};

/// Choose the mode that fits the resource's access pattern, returning null
/// only when the device reports no usable mode. The caller still has to
/// validate API usage flags and synchronization before allocating a resource.
pub fn chooseStorage(device: Device, use: ResourceUse) ?StorageMode {
    const cpu_visible = use == .cpu_stream_write or use == .cpu_readback;
    if (cpu_visible) {
        if (device.unified_memory and device.shared_supported) return .shared;
        if (device.managed_supported) return .managed;
        if (device.shared_supported) return .shared;
        return null;
    }

    if (device.private_supported) return .private;
    if (device.unified_memory and device.shared_supported) return .shared;
    if (device.managed_supported) return .managed;
    if (device.shared_supported) return .shared;
    return null;
}

test "shared UMA storage is reserved for CPU-visible streaming and readback" {
    const apple_silicon = Device{
        .unified_memory = true,
        .shared_supported = true,
        .managed_supported = false,
        .private_supported = true,
    };
    try std.testing.expectEqual(StorageMode.shared, chooseStorage(apple_silicon, .cpu_stream_write).?);
    try std.testing.expectEqual(StorageMode.shared, chooseStorage(apple_silicon, .cpu_readback).?);
    try std.testing.expectEqual(StorageMode.private, chooseStorage(apple_silicon, .gpu_sampled_texture).?);
    try std.testing.expectEqual(StorageMode.private, chooseStorage(apple_silicon, .gpu_transient_attachment).?);
}

test "discrete memory devices prefer managed storage for CPU-visible resources" {
    const discrete = Device{
        .unified_memory = false,
        .shared_supported = true,
        .managed_supported = true,
        .private_supported = true,
    };
    try std.testing.expectEqual(StorageMode.managed, chooseStorage(discrete, .cpu_stream_write).?);
    try std.testing.expectEqual(StorageMode.private, chooseStorage(discrete, .gpu_storage_texture).?);
}

test "storage policy reports an unsupported device instead of inventing a mode" {
    const no_storage = Device{
        .unified_memory = false,
        .shared_supported = false,
        .managed_supported = false,
        .private_supported = false,
    };
    try std.testing.expect(chooseStorage(no_storage, .gpu_sampled_texture) == null);
    try std.testing.expect(chooseStorage(no_storage, .cpu_readback) == null);
}
