//! Vulkan instance and device extension discovery and guest ABI marshalling.
//!
//! The host loader owns host extension strings; a PE guest owns guest
//! addresses. This module snapshots the host table, applies the one supported
//! Windows-to-Metal extension alias, and writes bounded Vulkan results into
//! guest memory.

const std = @import("std");
const abi = @import("gpu").vulkan.abi;
const guest_context = @import("guest_context");

const log = std.log.scoped(.vulkan_extensions);
extern fn dlsym(handle: *anyopaque, symbol: [*:0]const u8) ?*anyopaque;

pub const synthetic_instance_names = [_][]const u8{
    "VK_KHR_surface",
    "VK_KHR_win32_surface",
    "VK_EXT_metal_surface",
    "VK_KHR_portability_enumeration",
    "VK_KHR_get_physical_device_properties2",
};

pub const synthetic_device_names = [_][]const u8{
    "VK_KHR_swapchain",
    "VK_KHR_portability_subset",
    "VK_KHR_maintenance1",
};

pub const GuestInstanceExtensionAlias = struct {
    guest_name: []const u8,
    host_name: []const u8,
    spec_version: u32,
};

/// A Windows guest asks for a Win32 presentation surface while this host
/// uses Metal. Enumeration exposes the guest name only when its Metal alias
/// is available, and instance creation maps that same name to Metal.
pub const guest_aliases = [_]GuestInstanceExtensionAlias{
    .{
        .guest_name = "VK_KHR_win32_surface",
        .host_name = "VK_EXT_metal_surface",
        .spec_version = 6,
    },
};

fn initializationFailed() u64 {
    return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
}

fn resultValue(result: abi.Result) u64 {
    return @as(u32, @bitCast(result));
}

pub fn queryHost(cache: anytype, library: *anyopaque) bool {
    if (cache.host_instance_extensions_known) return true;
    const address = dlsym(library, "vkEnumerateInstanceExtensionProperties") orelse {
        log.err("host Vulkan loader has no vkEnumerateInstanceExtensionProperties", .{});
        return false;
    };
    const enumerate: abi.PfnEnumerateInstanceExtensionProperties = @ptrCast(@alignCast(address));
    var count: u32 = 0;
    const first = enumerate(null, &count, null);
    if (first != abi.SUCCESS and first != abi.INCOMPLETE) {
        log.err("host Vulkan instance extension count query failed: VkResult={d}", .{first});
        return false;
    }
    const capacity: u32 = @intCast(cache.host_instance_extensions.len);
    if (count > capacity) {
        log.err("host Vulkan instance extension list exceeds bridge capacity: count={d} capacity={d}", .{ count, capacity });
        return false;
    }
    var requested = count;
    if (requested != 0) {
        const second = enumerate(null, &requested, &cache.host_instance_extensions);
        if (second != abi.SUCCESS and second != abi.INCOMPLETE) {
            log.err("host Vulkan instance extension list query failed: VkResult={d} capacity={d}", .{ second, count });
            return false;
        }
    }
    if (requested > capacity) {
        log.err("host Vulkan instance extension list changed beyond bridge capacity: reported={d} capacity={d}", .{ requested, capacity });
        return false;
    }
    cache.host_instance_extension_count = requested;
    cache.host_instance_extensions_known = true;
    log.info("host Vulkan instance extensions cached: count={d} capacity={d} result={d}", .{ requested, capacity, first });
    return true;
}

pub fn hostAvailable(cache: anytype, name: []const u8) bool {
    if (!cache.host_instance_extensions_known) return true;
    const count: usize = @intCast(cache.host_instance_extension_count);
    for (cache.host_instance_extensions[0..count]) |*property| {
        if (std.mem.eql(u8, property.name(), name)) return true;
    }
    return false;
}

pub fn guestAlias(name: []const u8) ?[]const u8 {
    for (guest_aliases) |alias| {
        if (std.mem.eql(u8, name, alias.guest_name)) return alias.host_name;
    }
    return null;
}

pub fn guestAvailable(cache: anytype, name: []const u8) bool {
    if (hostAvailable(cache, name)) return true;
    const host_name = guestAlias(name) orelse return false;
    return hostAvailable(cache, host_name);
}

/// Enumerate the host extensions plus supported guest-facing aliases. The
/// SysV arguments are read from the calling guest thread's own register file
/// (`guest_context.registers`), which is the only file it may touch.
pub fn enumerateGuest(cache: anytype, state: anytype, call_index: u64) u64 {
    const layer_address = guest_context.registers(state).rdi;
    const count_address = guest_context.registers(state).rsi;
    const properties_address = guest_context.registers(state).rdx;
    const layer = if (layer_address == 0) null else state.guestCString(layer_address, 256);

    if (layer_address != 0) {
        const result = enumerateNoLayer(state, count_address);
        logEnumeration(call_index, layer_address, layer, count_address, properties_address, null, result, 0);
        return result;
    }

    if (cache.host_instance_extensions_known) {
        const host_count: usize = @intCast(cache.host_instance_extension_count);
        var exposed: [cache.host_instance_extensions.len + guest_aliases.len]abi.ExtensionProperties = undefined;
        var exposed_count = host_count;
        @memcpy(exposed[0..host_count], cache.host_instance_extensions[0..host_count]);
        for (guest_aliases) |alias| {
            if (hostAvailable(cache, alias.guest_name) or
                !hostAvailable(cache, alias.host_name) or
                exposed_count >= exposed.len)
            {
                continue;
            }
            exposed[exposed_count] = .{
                .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
                .spec_version = alias.spec_version,
            };
            @memcpy(exposed[exposed_count].extension_name[0..alias.guest_name.len], alias.guest_name);
            exposed_count += 1;
        }
        const count_before = readableCount(state, count_address);
        const result = writeProperties(state, count_address, properties_address, exposed[0..exposed_count]);
        logEnumeration(call_index, layer_address, layer, count_address, properties_address, count_before, result, exposed_count);
        return result;
    }

    const table = comptime syntheticProperties(&synthetic_instance_names);
    const count_before = readableCount(state, count_address);
    const result = writeProperties(state, count_address, properties_address, &table);
    logEnumeration(call_index, layer_address, layer, count_address, properties_address, count_before, result, table.len);
    return result;
}

pub fn enumerateSyntheticInstance(state: anytype) u64 {
    if (guest_context.registers(state).rdi != 0) return enumerateNoLayer(state, guest_context.registers(state).rsi);
    const table = comptime syntheticProperties(&synthetic_instance_names);
    return writeProperties(state, guest_context.registers(state).rsi, guest_context.registers(state).rdx, &table);
}

pub fn enumerateSyntheticDevice(state: anytype) u64 {
    if (guest_context.registers(state).rsi != 0) return enumerateNoLayer(state, guest_context.registers(state).rdx);
    const table = comptime syntheticProperties(&synthetic_device_names);
    return writeProperties(state, guest_context.registers(state).rdx, guest_context.registers(state).rcx, &table);
}

pub fn writeProperties(
    state: anytype,
    count_address: u64,
    output_address: u64,
    available: []const abi.ExtensionProperties,
) u64 {
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return initializationFailed();
    const total: u32 = @intCast(available.len);
    if (output_address == 0) {
        state.write32(count_address, total);
        return resultValue(abi.SUCCESS);
    }
    const capacity = state.read32(count_address);
    const written: u32 = @min(capacity, total);
    if (written != 0) {
        const span = @as(u64, written) * @sizeOf(abi.ExtensionProperties);
        const bytes = state.guestMemory(output_address, span) orelse return initializationFailed();
        @memcpy(bytes[0..@intCast(span)], std.mem.sliceAsBytes(available[0..written]));
    }
    state.write32(count_address, written);
    return resultValue(if (written < total) abi.INCOMPLETE else abi.SUCCESS);
}

pub fn enumerateNoLayer(state: anytype, count_address: u64) u64 {
    if (count_address != 0 and state.guestMemory(count_address, 4) != null) state.write32(count_address, 0);
    return resultValue(abi.ERROR_LAYER_NOT_PRESENT);
}

pub fn syntheticProperties(comptime names: []const []const u8) [names.len]abi.ExtensionProperties {
    var table: [names.len]abi.ExtensionProperties = undefined;
    for (names, 0..) |name, index| {
        table[index] = .{ .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE, .spec_version = 1 };
        @memcpy(table[index].extension_name[0..name.len], name);
    }
    return table;
}

fn readableCount(state: anytype, address: u64) ?u32 {
    if (address == 0 or state.guestMemory(address, 4) == null) return null;
    return state.read32(address);
}

fn logEnumeration(
    call_index: u64,
    layer_address: u64,
    layer: ?[]const u8,
    count_address: u64,
    properties_address: u64,
    count_before: ?u32,
    result: u64,
    exposed_count: usize,
) void {
    if (call_index > 8 and (call_index & (call_index - 1)) != 0) return;
    const signed_result: i32 = @bitCast(@as(u32, @truncate(result)));
    log.info(
        "vkEnumerateInstanceExtensionProperties guest call={d}: pLayerName=0x{x} layer={s} pPropertyCount=0x{x} count_before_readable={} count_before={d} pProperties=0x{x} exposed={d} VkResult={d} (0x{x})",
        .{
            call_index,
            layer_address,
            layer orelse "<null-or-unreadable>",
            count_address,
            count_before != null,
            count_before orelse 0,
            properties_address,
            exposed_count,
            signed_result,
            result,
        },
    );
}

const TestState = struct {
    mem: [131_072]u8 = @splat(0),
    regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},

    fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
        const capacity: u64 = @intCast(self.mem.len);
        if (address > capacity or length > capacity - address) return null;
        return self.mem[@intCast(address)..][0..@intCast(length)];
    }

    fn read32(self: *@This(), address: u64) u32 {
        return std.mem.readInt(u32, self.mem[@intCast(address)..][0..4], .little);
    }

    fn write32(self: *@This(), address: u64, value: u32) void {
        std.mem.writeInt(u32, self.mem[@intCast(address)..][0..4], value, .little);
    }

    fn guestCString(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
        const bytes = self.guestMemory(address, @intCast(@min(maximum, self.mem.len) + 1)) orelse return null;
        const end = std.mem.indexOfScalar(u8, bytes, 0) orelse return null;
        return bytes[0..end];
    }
};

const TestCache = struct {
    host_instance_extensions: [64]abi.ExtensionProperties = [_]abi.ExtensionProperties{.{
        .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
        .spec_version = 0,
    }} ** 64,
    host_instance_extension_count: u32 = 0,
    host_instance_extensions_known: bool = false,

    fn append(self: *@This(), name: []const u8, spec_version: u32) void {
        const index: usize = @intCast(self.host_instance_extension_count);
        self.host_instance_extensions[index] = .{
            .extension_name = [_]u8{0} ** abi.MAX_EXTENSION_NAME_SIZE,
            .spec_version = spec_version,
        };
        @memcpy(self.host_instance_extensions[index].extension_name[0..name.len], name);
        self.host_instance_extension_count += 1;
    }
};

test "instance extension enumeration uses the two-call guest protocol and adds only available aliases" {
    var cache = TestCache{};
    cache.host_instance_extensions_known = true;
    cache.append("VK_KHR_surface", 25);
    cache.append("VK_EXT_metal_surface", 1);
    var state = TestState{};
    const count_address: u64 = 8;
    const array_address: u64 = 64;
    state.regs = .{ .rdi = 0, .rsi = count_address, .rdx = 0 };

    try std.testing.expectEqual(@as(u64, 0), enumerateGuest(&cache, &state, 1));
    try std.testing.expectEqual(@as(u32, 3), state.read32(count_address));

    state.regs.rdx = array_address;
    try std.testing.expectEqual(@as(u64, 0), enumerateGuest(&cache, &state, 2));
    try std.testing.expectEqual(@as(u32, 3), state.read32(count_address));
    const first = @as(usize, @intCast(array_address));
    try std.testing.expectEqualStrings("VK_KHR_surface", std.mem.sliceTo(state.mem[first..][0..abi.MAX_EXTENSION_NAME_SIZE], 0));
    const alias_offset = first + 2 * @sizeOf(abi.ExtensionProperties);
    try std.testing.expectEqualStrings("VK_KHR_win32_surface", std.mem.sliceTo(state.mem[alias_offset..][0..abi.MAX_EXTENSION_NAME_SIZE], 0));
}

test "extension enumeration reports VK_INCOMPLETE only for a short guest array" {
    const available = [_]abi.ExtensionProperties{
        syntheticProperties(&.{"VK_KHR_swapchain"})[0],
        syntheticProperties(&.{"VK_KHR_portability_subset"})[0],
        syntheticProperties(&.{"VK_KHR_maintenance1"})[0],
    };
    var state = TestState{};
    const count_address: u64 = 8;
    const array_address: u64 = 64;

    state.write32(count_address, 2);
    try std.testing.expectEqual(resultValue(abi.INCOMPLETE), writeProperties(&state, count_address, array_address, &available));
    try std.testing.expectEqual(@as(u32, 2), state.read32(count_address));
    try std.testing.expectEqualStrings("VK_KHR_swapchain", std.mem.sliceTo(state.mem[64..320], 0));
    try std.testing.expectEqualStrings("VK_KHR_portability_subset", std.mem.sliceTo(state.mem[324..580], 0));
    try std.testing.expectEqual(@as(u8, 0), state.mem[584]);

    state.write32(count_address, 0);
    try std.testing.expectEqual(resultValue(abi.INCOMPLETE), writeProperties(&state, count_address, array_address, &available));
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));
    try std.testing.expectEqual(initializationFailed(), writeProperties(&state, state.mem.len + 8, 0, &available));
}

test "a non-null layer name returns VK_ERROR_LAYER_NOT_PRESENT" {
    var state = TestState{};
    const count_address: u64 = 8;
    @memcpy(state.mem[1024..][0.."VK_LAYER_KHRONOS_validation".len], "VK_LAYER_KHRONOS_validation");
    state.regs = .{ .rdi = 1024, .rsi = count_address, .rdx = 64 };
    state.write32(count_address, 4);

    try std.testing.expectEqual(resultValue(abi.ERROR_LAYER_NOT_PRESENT), enumerateGuest(&TestCache{}, &state, 1));
    try std.testing.expectEqual(@as(u32, 0), state.read32(count_address));
}

test "synthetic instance and device lists expose the same names they write" {
    var state = TestState{};
    const count_address: u64 = 8;
    state.regs = .{ .rdi = 0, .rsi = count_address, .rdx = 0 };
    try std.testing.expectEqual(resultValue(abi.SUCCESS), enumerateSyntheticInstance(&state));
    try std.testing.expectEqual(@as(u32, synthetic_instance_names.len), state.read32(count_address));

    state.regs = .{ .rsi = 0, .rdx = count_address, .rcx = 0 };
    try std.testing.expectEqual(resultValue(abi.SUCCESS), enumerateSyntheticDevice(&state));
    try std.testing.expectEqual(@as(u32, synthetic_device_names.len), state.read32(count_address));
}
