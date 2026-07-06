const std = @import("std");
const runtime_abi = @import("runtime_abi_handshake");
const reg_trace = @import("register-tracing/runtime.zig");
const exception_trace = @import("exceptions/runtime.zig");
const modes = @import("modes/root.zig");

pub const Register64 = enum(u5) {
    rax,
    rcx,
    rdx,
    rbx,
    rsp,
    rbp,
    rsi,
    rdi,
    r8,
    r9,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,
};

pub const RegisterFile64 = struct {
    pub const AbiMode = enum(u8) {
        windows_x64 = 1,
        systemv_amd64 = 2,
        macos_arm64_host = 3,
        guest_vs_host = 4,
    };

    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    rbx: u64 = 0,
    rsp: u64 = 0,
    rbp: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rip: u64 = 0,
    rflags: u64 = 0,
    fs_base: u64 = 0,
    gs_base: u64 = 0,
    xmm: [16]u128 = [_]u128{0} ** 16,
    abi_mode: AbiMode = .windows_x64,
    host_abi_mode: AbiMode = .macos_arm64_host,
    shadow_space_bytes: u8 = 0,
    varargs_duplicate_mask: u8 = 0,
    struct_return_ptr: u64 = 0,
    unwind_info_present: bool = false,
    seh_scope_present: bool = false,
    guest_call_boundary: bool = false,

    pub fn get(self: *const RegisterFile64, reg: Register64) u64 {
        return switch (reg) {
            .rax => self.rax,
            .rcx => self.rcx,
            .rdx => self.rdx,
            .rbx => self.rbx,
            .rsp => self.rsp,
            .rbp => self.rbp,
            .rsi => self.rsi,
            .rdi => self.rdi,
            .r8 => self.r8,
            .r9 => self.r9,
            .r10 => self.r10,
            .r11 => self.r11,
            .r12 => self.r12,
            .r13 => self.r13,
            .r14 => self.r14,
            .r15 => self.r15,
        };
    }

    pub fn set(self: *RegisterFile64, reg: Register64, value: u64) void {
        switch (reg) {
            .rax => self.rax = value,
            .rcx => self.rcx = value,
            .rdx => self.rdx = value,
            .rbx => self.rbx = value,
            .rsp => self.rsp = value,
            .rbp => self.rbp = value,
            .rsi => self.rsi = value,
            .rdi => self.rdi = value,
            .r8 => self.r8 = value,
            .r9 => self.r9 = value,
            .r10 => self.r10 = value,
            .r11 => self.r11 = value,
            .r12 => self.r12 = value,
            .r13 => self.r13 = value,
            .r14 => self.r14 = value,
            .r15 => self.r15 = value,
        }
    }

    pub fn xmmLow64(self: *const RegisterFile64, index: usize) u64 {
        return @truncate(self.xmm[index]);
    }

    pub fn calleeSavedMask(self: *const RegisterFile64) u16 {
        var mask: u16 = 0;
        if (self.rbx != 0) mask |= 1 << 0;
        if (self.rbp != 0) mask |= 1 << 1;
        if (self.rdi != 0) mask |= 1 << 2;
        if (self.rsi != 0) mask |= 1 << 3;
        if (self.r12 != 0) mask |= 1 << 4;
        if (self.r13 != 0) mask |= 1 << 5;
        if (self.r14 != 0) mask |= 1 << 6;
        if (self.r15 != 0) mask |= 1 << 7;
        var i: usize = 6;
        while (i <= 15) : (i += 1) {
            if (self.xmm[i] != 0) mask |= @as(u16, 1) << @intCast(i + 2);
        }
        return mask;
    }
};

pub const X64State = struct {
    regs: RegisterFile64 = .{},

    /// Memory model configuration for this x64 state
    memory_config: modes.MemoryModelConfig = modes.memory.longModeDefaults(),

    pub fn instructionPointer(self: *X64State) *u64 {
        return &self.regs.rip;
    }

    pub fn stackPointer(self: *X64State) *u64 {
        return &self.regs.rsp;
    }

    /// Get current operating mode
    pub fn operatingMode(self: *const X64State) modes.OperatingMode {
        return self.memory_config.operating_mode;
    }

    /// Get current memory model
    pub fn memoryModel(self: *const X64State) modes.MemoryModel {
        return self.memory_config.memory_model;
    }

    /// Translate effective address to linear address
    pub fn effectiveToLinear(self: *const X64State, effective: u64, segment: enum { cs, ds, es, ss, fs, gs }) !modes.LinearAddress {
        return modes.memory.effectiveToLinear(&self.memory_config, effective, switch (segment) {
            .cs => .cs,
            .ds => .ds,
            .es => .es,
            .ss => .ss,
            .fs => .fs,
            .gs => .gs,
        });
    }

    /// Set operating mode (reconfigures memory model appropriately)
    pub fn setOperatingMode(self: *X64State, mode: modes.OperatingMode) void {
        self.memory_config = switch (mode) {
            .long_mode => modes.memory.longModeDefaults(),
            .compatibility => modes.memory.compatibilityModeDefaults(),
            .system_management => modes.memory.systemManagementDefaults(),
        };
    }

    /// Check if address is canonical
    pub fn isCanonical(self: *const X64State, addr: u64) bool {
        _ = self;
        return modes.memory.isCanonicalAddress(addr);
    }
};

test "x64 state covers extended registers and pointers" {
    reg_trace.init();
    defer reg_trace.deinit();
    var state: X64State = .{};
    state.regs.r13 = 0xCAFE_BABE;
    state.regs.rip = 0x1400_1000;
    state.regs.rsp = 0x7FFF_F000;
    state.regs.rflags = 0x2;
    state.regs.fs_base = 1;
    state.regs.shadow_space_bytes = 32;
    state.regs.guest_call_boundary = true;
    state.regs.unwind_info_present = true;
    runtime_abi.x64.validateState("x64-state-test", &state.regs);
    reg_trace.logCheckpoint("x64-state-test", &state.regs);
    exception_trace.logStructuredException("x64-state-test", 0xC0000005, state.regs.rip, &state.regs);
    try std.testing.expectEqual(@as(u64, 0xCAFE_BABE), state.regs.get(.r13));
    try std.testing.expectEqual(@as(u64, 0x1400_1000), state.instructionPointer().*);
}

test "x64 state memory model integration" {
    var state: X64State = .{};
    try std.testing.expectEqual(modes.OperatingMode.long_mode, state.operatingMode());
    try std.testing.expectEqual(modes.MemoryModel.flat_64, state.memoryModel());

    const linear = try state.effectiveToLinear(0x4000, .cs);
    try std.testing.expectEqual(@as(u64, 0x4000), linear);

    try std.testing.expect(state.isCanonical(0x0000_0000_0000_0000));
    try std.testing.expect(state.isCanonical(0x0000_7FFF_FFFF_FFFF));
    try std.testing.expect(!state.isCanonical(0x0000_8000_0000_0000));

    state.setOperatingMode(.compatibility);
    try std.testing.expectEqual(modes.OperatingMode.compatibility, state.operatingMode());
    try std.testing.expectEqual(modes.MemoryModel.compatibility_segmented, state.memoryModel());
}
