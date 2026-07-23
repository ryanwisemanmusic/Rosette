const std = @import("std");

pub const GuestAddress = u32;
pub const HostAddress = u64;

pub const ThunkKind = enum {
    host_to_guest,
    guest_to_host,
};

pub const RegisterConvention = enum {
    system_v,
    microsoft_x64,
};

pub const HostToGuestThunk = struct {
    host_addr: HostAddress,
    guest_addr: GuestAddress,
    thunk_size: usize,
    stack_frame_size: usize,
};

pub const GuestToHostThunk = struct {
    host_addr: HostAddress,
    handler_addr: HostAddress,
    thunk_size: usize,
};

pub const CodeCacheLayout = struct {
    base_addr: HostAddress,
    size: usize,
    page_size: usize,
    current_offset: usize,
    num_regions: u32,
};

pub const ModuleEntry = struct {
    name: []const u8,
    base_guest_addr: GuestAddress,
    size: usize,
    entry_point: GuestAddress,
    is_executable: bool,
    num_functions: u32,
};

pub const SystemVAbi = struct {
    pub const arg_regs = [_]u32{ 0x7F, 0x7E, 0x7D, 0x7C, 0x7B, 0x7A };
    pub const callee_saved = [_]u32{
        0x78, 0x77, 0x76, 0x75, 0x74, 0x73,
    };
    pub const stack_alignment: u32 = 16;
    pub const red_zone_size: u32 = 128;
};

pub const XeniaConstants = struct {
    pub const sentinel_return_address: u32 = 0xBCBCBCBC;
    pub const default_stack_padding: u32 = 64 + 112;
    pub const trampoline_base: u32 = 0x80040000;
    pub const trampoline_size: u32 = 0x001C0000;
    pub const xex_entry_point_magic: u32 = 0x100;
    pub const max_guest_functions: u32 = 1_000_000;
    pub const default_code_cache_size: usize = 64 * 1024 * 1024;
};

pub const KnownGuestModule = struct {
    name: []const u8,
    base_addr: GuestAddress,
    size: usize,

    pub const xboxkrnl = KnownGuestModule{
        .name = "xboxkrnl.exe",
        .base_addr = 0x80000000,
        .size = 0x001C0000,
    };

    pub const xam = KnownGuestModule{
        .name = "xam.xex",
        .base_addr = 0x801C0000,
        .size = 0x00200000,
    };

    pub const game_module = KnownGuestModule{
        .name = "<game>",
        .base_addr = 0x82000000,
        .size = 0x01000000,
    };
};

test "System V ABI constants are sane" {
    try std.testing.expectEqual(@as(u32, 6), SystemVAbi.arg_regs.len);
    try std.testing.expectEqual(@as(u32, 6), SystemVAbi.callee_saved.len);
    try std.testing.expectEqual(@as(u32, 16), SystemVAbi.stack_alignment);
}

test "XeniaConstants sentinel is correct" {
    try std.testing.expectEqual(@as(u32, 0xBCBCBCBC), XeniaConstants.sentinel_return_address);
    try std.testing.expectEqual(@as(u32, 0x80040000), XeniaConstants.trampoline_base);
}

test "KnownGuestModule addresses are mutually exclusive" {
    try std.testing.expect(KnownGuestModule.xboxkrnl.base_addr < KnownGuestModule.xam.base_addr);
    try std.testing.expect(KnownGuestModule.xam.base_addr < KnownGuestModule.game_module.base_addr);

    const xboxkrnl_end = KnownGuestModule.xboxkrnl.base_addr + KnownGuestModule.xboxkrnl.size;
    try std.testing.expect(xboxkrnl_end <= KnownGuestModule.xam.base_addr);
}
