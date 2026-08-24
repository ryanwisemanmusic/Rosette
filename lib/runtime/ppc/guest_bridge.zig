//! Adapter for a direct PPC embedder that is itself running as translated code.
//!
//! The public `host_abi` contract describes native pointers. Xenia's direct
//! backend is reached through a guest x86-64 `dlsym` thunk, so every pointer in
//! `RosettePpcGuestState` is a Rosette guest address instead. This adapter is
//! the live boundary between those two worlds:
//!
//!   guest x86 memory -> checked GuestMemory callbacks -> shadow PPC state
//!   PPC callback -> Mach-O guest call -> Xenia's canonical PPCContext
//!
//! The instruction runtime remains reusable and knows nothing about Mach-O or
//! Xenia. Only this adapter owns the guest-address parsing and synchronization.

const std = @import("std");
const host_abi = @import("host_abi.zig");
const memory_mod = @import("memory.zig");

pub const GuestMemory = struct {
    context: *anyopaque,
    read: *const fn (*anyopaque, u64, []u8) bool,
    write: *const fn (*anyopaque, u64, []const u8) bool,
    /// Optional PPC/Xbox address-space callbacks. The base callbacks address
    /// Rosette's translated x86 guest memory, which is where the ABI record
    /// and its register/callback pointers live. PPC instruction/data accesses
    /// may instead use Xenia's Xbox virtual address mapping.
    read_ppc: ?*const fn (*anyopaque, u64, []u8) bool = null,
    write_ppc: ?*const fn (*anyopaque, u64, []const u8) bool = null,
    alloc: *const fn (*anyopaque, u64, u64) ?u64,
};

pub const GuestCall = *const fn (*anyopaque, u64, [6]u64) u64;

pub const BindFailure = enum {
    none,
    guest_state_unreadable,
    missing_callback,
    invalid_address_space_size,
    no_slot,
    register_state_unreadable,
    host_binding_rejected,
};

const GuestPointers = struct {
    gpr: u64,
    fpr: u64,
    vr: u64,
    lr: u64,
    ctr: u64,
    msr: u64,
    fpscr: u64,
    xer_ca: u64,
    xer_ov: u64,
    xer_so: u64,
    vscr_sat: u64,
    vrsave: u64,
    reserved_val: u64,
    virtual_membase: u64,
    guest_address_space_size: u64,
    host_context: u64,
    read_cr: u64,
    write_cr: u64,
    system_call: u64,
    resolve_call: u64,
    trap: u64,
};

const Slot = struct {
    used: bool = false,
    guest_state_address: u64 = 0,
    guest: GuestPointers = undefined,
    guest_memory: GuestMemory = undefined,
    call_context: *anyopaque = undefined,
    call_guest: GuestCall = undefined,

    gpr: [32]u64 = [_]u64{0} ** 32,
    fpr: [32]f64 = [_]f64{0} ** 32,
    vr: [128][4]u32 = [_][4]u32{.{ 0, 0, 0, 0 }} ** 128,
    lr: u64 = 0,
    ctr: u64 = 0,
    msr: u64 = 0,
    fpscr: u32 = 0,
    xer_ca: u8 = 0,
    xer_ov: u8 = 0,
    xer_so: u8 = 0,
    vscr_sat: u8 = 0,
    vrsave: u32 = 0,
    reserved_val: u64 = 0,
    host_state: host_abi.GuestState = undefined,
};

const max_slots = 64;

pub const Bridge = struct {
    slots: [max_slots]Slot = [_]Slot{.{}} ** max_slots,
    last_bind_failure: BindFailure = .none,

    pub fn deinit(self: *Bridge) void {
        for (&self.slots) |*slot| {
            if (!slot.used) continue;
            host_abi.rosette_ppc_release_context(@ptrCast(slot));
            slot.* = .{};
        }
    }

    pub fn bind(
        self: *Bridge,
        guest_state_address: u64,
        guest_memory: GuestMemory,
        call_context: *anyopaque,
        call_guest: GuestCall,
    ) bool {
        self.last_bind_failure = .none;
        const pointers = parseGuestState(guest_memory, guest_state_address) orelse {
            self.last_bind_failure = .guest_state_unreadable;
            return false;
        };
        if (pointers.host_context == 0 or pointers.read_cr == 0 or
            pointers.write_cr == 0 or pointers.system_call == 0 or
            pointers.resolve_call == 0 or pointers.trap == 0)
        {
            self.last_bind_failure = .missing_callback;
            return false;
        }
        if (pointers.guest_address_space_size == 0 or
            pointers.guest_address_space_size > @as(u64, std.math.maxInt(u32)) + 1)
        {
            self.last_bind_failure = .invalid_address_space_size;
            return false;
        }

        var slot = self.findGuestContext(pointers.host_context) orelse self.freeSlot() orelse {
            self.last_bind_failure = .no_slot;
            return false;
        };
        if (slot.used) host_abi.rosette_ppc_release_context(@ptrCast(slot));
        slot.* = .{
            .used = true,
            .guest_state_address = guest_state_address,
            .guest = pointers,
            .guest_memory = guest_memory,
            .call_context = call_context,
            .call_guest = call_guest,
        };
        slot.host_state = makeHostState(slot);
        if (!syncGuestToShadow(slot)) {
            self.last_bind_failure = .register_state_unreadable;
            slot.* = .{};
            return false;
        }

        const ppc_memory = memory_mod.Memory.fromCallbacks(
            .{
                .context = @ptrCast(slot),
                .read = memoryRead,
                .write = memoryWrite,
            },
            @intCast(pointers.guest_address_space_size),
            0,
        );
        if (host_abi.bindContextWithMemory(&slot.host_state, ppc_memory) == 0) {
            self.last_bind_failure = .host_binding_rejected;
            slot.* = .{};
            return false;
        }
        return true;
    }

    pub fn release(self: *Bridge, guest_host_context: u64) void {
        const slot = self.findGuestContext(guest_host_context) orelse return;
        host_abi.rosette_ppc_release_context(@ptrCast(slot));
        slot.* = .{};
    }

    pub fn execute(
        self: *Bridge,
        guest_host_context: u64,
        address: u32,
        return_address: u32,
        result_address: u64,
    ) bool {
        const slot = self.findGuestContext(guest_host_context) orelse return false;
        if (!syncGuestToShadow(slot)) return false;

        var result: host_abi.RunResult = undefined;
        host_abi.rosette_ppc_execute(@ptrCast(slot), address, return_address, &result);
        if (!syncShadowToGuest(slot)) return false;
        return writeRunResult(slot, result_address, result);
    }

    pub fn stats(
        self: *Bridge,
        guest_host_context: u64,
        out_blocks_address: u64,
        out_instructions_address: u64,
    ) bool {
        const slot = self.findGuestContext(guest_host_context) orelse return false;
        var blocks: u64 = 0;
        var instructions: u64 = 0;
        if (host_abi.rosette_ppc_recompiler_stats(@ptrCast(slot), &blocks, &instructions) == 0) return false;
        return writeInt(slot.guest_memory, out_blocks_address, blocks) and
            writeInt(slot.guest_memory, out_instructions_address, instructions);
    }

    pub fn invalidateRange(_: *Bridge, guest_low: u32, guest_high: u32) void {
        host_abi.rosette_ppc_invalidate_range(guest_low, guest_high);
    }

    fn findGuestContext(self: *Bridge, guest_host_context: u64) ?*Slot {
        for (&self.slots) |*slot| {
            if (slot.used and slot.guest.host_context == guest_host_context) return slot;
        }
        return null;
    }

    fn freeSlot(self: *Bridge) ?*Slot {
        for (&self.slots) |*slot| if (!slot.used) return slot;
        return null;
    }
};

fn makeHostState(slot: *Slot) host_abi.GuestState {
    return .{
        .abi_version = host_abi.abi_version,
        .reserved = 0,
        .gpr = &slot.gpr,
        .fpr = &slot.fpr,
        .vr = &slot.vr,
        .lr = &slot.lr,
        .ctr = &slot.ctr,
        .msr = &slot.msr,
        .fpscr = &slot.fpscr,
        .xer_ca = &slot.xer_ca,
        .xer_ov = &slot.xer_ov,
        .xer_so = &slot.xer_so,
        .vscr_sat = &slot.vscr_sat,
        .vrsave = &slot.vrsave,
        .reserved_val = &slot.reserved_val,
        // The callback Memory override means this pointer is never
        // dereferenced. Keep it non-null so an accidental fallback is easy to
        // identify in a debugger rather than looking like a null ABI field.
        .virtual_membase = @ptrFromInt(1),
        .guest_address_space_size = slot.guest.guest_address_space_size,
        .host_context = @ptrCast(slot),
        .read_cr = readCr,
        .write_cr = writeCr,
        .system_call = systemCall,
        .resolve_call = resolveCall,
        .trap = trap,
    };
}

fn memoryRead(context: *anyopaque, address: u32, destination: []u8) bool {
    const slot: *Slot = @ptrCast(@alignCast(context));
    const read = slot.guest_memory.read_ppc orelse slot.guest_memory.read;
    return read(slot.guest_memory.context, address, destination);
}

fn memoryWrite(context: *anyopaque, address: u32, source: []const u8) bool {
    const slot: *Slot = @ptrCast(@alignCast(context));
    const write = slot.guest_memory.write_ppc orelse slot.guest_memory.write;
    return write(slot.guest_memory.context, address, source);
}

fn readCr(context: *anyopaque) callconv(.c) u32 {
    const slot: *Slot = @ptrCast(@alignCast(context));
    const result = slot.call_guest(slot.call_context, slot.guest.read_cr, .{ slot.guest.host_context, 0, 0, 0, 0, 0 });
    _ = syncGuestToShadow(slot);
    return @truncate(result);
}

fn writeCr(context: *anyopaque, value: u32) callconv(.c) void {
    const slot: *Slot = @ptrCast(@alignCast(context));
    _ = slot.call_guest(slot.call_context, slot.guest.write_cr, .{ slot.guest.host_context, value, 0, 0, 0, 0 });
    _ = syncGuestToShadow(slot);
}

fn systemCall(context: *anyopaque, lev: u32, instruction_address: u32) callconv(.c) i32 {
    const slot: *Slot = @ptrCast(@alignCast(context));
    const result = slot.call_guest(
        slot.call_context,
        slot.guest.system_call,
        .{ slot.guest.host_context, lev, instruction_address, 0, 0, 0 },
    );
    _ = syncGuestToShadow(slot);
    return @bitCast(@as(u32, @truncate(result)));
}

fn resolveCall(context: *anyopaque, target_address: u32, return_address: u32) callconv(.c) i32 {
    const slot: *Slot = @ptrCast(@alignCast(context));
    const result = slot.call_guest(
        slot.call_context,
        slot.guest.resolve_call,
        .{ slot.guest.host_context, target_address, return_address, 0, 0, 0 },
    );
    _ = syncGuestToShadow(slot);
    return @bitCast(@as(u32, @truncate(result)));
}

fn trap(context: *anyopaque, instruction_address: u32) callconv(.c) void {
    const slot: *Slot = @ptrCast(@alignCast(context));
    _ = slot.call_guest(
        slot.call_context,
        slot.guest.trap,
        .{ slot.guest.host_context, instruction_address, 0, 0, 0, 0 },
    );
    _ = syncGuestToShadow(slot);
}

fn parseGuestState(guest_memory: GuestMemory, address: u64) ?GuestPointers {
    if (readInt(guest_memory, address + @offsetOf(host_abi.GuestState, "abi_version"), u32) != host_abi.abi_version) return null;
    return .{
        .gpr = readPtr(guest_memory, address, "gpr") orelse return null,
        .fpr = readPtr(guest_memory, address, "fpr") orelse return null,
        .vr = readPtr(guest_memory, address, "vr") orelse return null,
        .lr = readPtr(guest_memory, address, "lr") orelse return null,
        .ctr = readPtr(guest_memory, address, "ctr") orelse return null,
        .msr = readPtr(guest_memory, address, "msr") orelse return null,
        .fpscr = readPtr(guest_memory, address, "fpscr") orelse return null,
        .xer_ca = readPtr(guest_memory, address, "xer_ca") orelse return null,
        .xer_ov = readPtr(guest_memory, address, "xer_ov") orelse return null,
        .xer_so = readPtr(guest_memory, address, "xer_so") orelse return null,
        .vscr_sat = readPtr(guest_memory, address, "vscr_sat") orelse return null,
        .vrsave = readPtr(guest_memory, address, "vrsave") orelse return null,
        .reserved_val = readPtr(guest_memory, address, "reserved_val") orelse return null,
        .virtual_membase = readPtr(guest_memory, address, "virtual_membase") orelse return null,
        .guest_address_space_size = readIntField(guest_memory, address, "guest_address_space_size") orelse return null,
        .host_context = readPtr(guest_memory, address, "host_context") orelse return null,
        .read_cr = readPtr(guest_memory, address, "read_cr") orelse return null,
        .write_cr = readPtr(guest_memory, address, "write_cr") orelse return null,
        .system_call = readPtr(guest_memory, address, "system_call") orelse return null,
        .resolve_call = readPtr(guest_memory, address, "resolve_call") orelse return null,
        .trap = readPtr(guest_memory, address, "trap") orelse return null,
    };
}

fn readPtr(guest_memory: GuestMemory, base: u64, comptime field: []const u8) ?u64 {
    return readIntField(guest_memory, base, field);
}

fn readIntField(guest_memory: GuestMemory, base: u64, comptime field: []const u8) ?u64 {
    return readInt(guest_memory, base + @offsetOf(host_abi.GuestState, field), u64);
}

fn readInt(guest_memory: GuestMemory, address: u64, comptime T: type) ?T {
    var bytes: [@sizeOf(T)]u8 = undefined;
    if (!guest_memory.read(guest_memory.context, address, &bytes)) return null;
    return std.mem.readInt(T, &bytes, .little);
}

fn writeInt(guest_memory: GuestMemory, address: u64, value: anytype) bool {
    const T = @TypeOf(value);
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    return guest_memory.write(guest_memory.context, address, &bytes);
}

fn readGuest(slot: *Slot, address: u64, comptime T: type) ?T {
    return readInt(slot.guest_memory, address, T);
}

fn writeGuest(slot: *Slot, address: u64, value: anytype) bool {
    return writeInt(slot.guest_memory, address, value);
}

fn syncGuestToShadow(slot: *Slot) bool {
    for (&slot.gpr, 0..) |*value, index| {
        value.* = readGuest(slot, slot.guest.gpr + index * @sizeOf(u64), u64) orelse return false;
    }
    for (&slot.fpr, 0..) |*value, index| {
        const bits = readGuest(slot, slot.guest.fpr + index * @sizeOf(u64), u64) orelse return false;
        value.* = @bitCast(bits);
    }
    for (&slot.vr, 0..) |*vector, index| {
        for (vector, 0..) |*lane, lane_index| {
            lane.* = readGuest(slot, slot.guest.vr + (index * 4 + lane_index) * @sizeOf(u32), u32) orelse return false;
        }
    }
    slot.lr = readGuest(slot, slot.guest.lr, u64) orelse return false;
    slot.ctr = readGuest(slot, slot.guest.ctr, u64) orelse return false;
    slot.msr = readGuest(slot, slot.guest.msr, u64) orelse return false;
    slot.fpscr = readGuest(slot, slot.guest.fpscr, u32) orelse return false;
    slot.xer_ca = readGuest(slot, slot.guest.xer_ca, u8) orelse return false;
    slot.xer_ov = readGuest(slot, slot.guest.xer_ov, u8) orelse return false;
    slot.xer_so = readGuest(slot, slot.guest.xer_so, u8) orelse return false;
    slot.vscr_sat = readGuest(slot, slot.guest.vscr_sat, u8) orelse return false;
    slot.vrsave = readGuest(slot, slot.guest.vrsave, u32) orelse return false;
    slot.reserved_val = readGuest(slot, slot.guest.reserved_val, u64) orelse return false;
    return true;
}

fn syncShadowToGuest(slot: *Slot) bool {
    for (slot.gpr, 0..) |value, index| {
        if (!writeGuest(slot, slot.guest.gpr + index * @sizeOf(u64), value)) return false;
    }
    for (slot.fpr, 0..) |value, index| {
        if (!writeGuest(slot, slot.guest.fpr + index * @sizeOf(u64), @as(u64, @bitCast(value)))) return false;
    }
    for (slot.vr, 0..) |vector, index| {
        for (vector, 0..) |lane, lane_index| {
            if (!writeGuest(slot, slot.guest.vr + (index * 4 + lane_index) * @sizeOf(u32), lane)) return false;
        }
    }
    return writeGuest(slot, slot.guest.lr, slot.lr) and
        writeGuest(slot, slot.guest.ctr, slot.ctr) and
        writeGuest(slot, slot.guest.msr, slot.msr) and
        writeGuest(slot, slot.guest.fpscr, slot.fpscr) and
        writeGuest(slot, slot.guest.xer_ca, slot.xer_ca) and
        writeGuest(slot, slot.guest.xer_ov, slot.xer_ov) and
        writeGuest(slot, slot.guest.xer_so, slot.xer_so) and
        writeGuest(slot, slot.guest.vscr_sat, slot.vscr_sat) and
        writeGuest(slot, slot.guest.vrsave, slot.vrsave) and
        writeGuest(slot, slot.guest.reserved_val, slot.reserved_val);
}

fn writeRunResult(slot: *Slot, address: u64, result: host_abi.RunResult) bool {
    if (!writeGuest(slot, address + @offsetOf(host_abi.RunResult, "status"), result.status)) return false;
    if (!writeGuest(slot, address + @offsetOf(host_abi.RunResult, "address"), result.address)) return false;
    if (!writeGuest(slot, address + @offsetOf(host_abi.RunResult, "instructions_retired"), result.instructions_retired)) return false;

    var opcode_guest_address: u64 = 0;
    if (result.unimplemented_opcode) |opcode| {
        const length = std.mem.len(opcode);
        opcode_guest_address = slot.guest_memory.alloc(slot.guest_memory.context, length + 1, 1) orelse return false;
        if (!slot.guest_memory.write(slot.guest_memory.context, opcode_guest_address, opcode[0..length])) return false;
        var zero = [_]u8{0};
        if (!slot.guest_memory.write(slot.guest_memory.context, opcode_guest_address + length, &zero)) return false;
    }
    return writeGuest(slot, address + @offsetOf(host_abi.RunResult, "unimplemented_opcode"), opcode_guest_address);
}

test "guest-memory callbacks preserve the PPC ABI's little-endian fields" {
    const Harness = struct {
        bytes: [64]u8 = [_]u8{0} ** 64,

        fn read(context: *anyopaque, address: u64, out: []u8) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (address + out.len > self.bytes.len) return false;
            @memcpy(out, self.bytes[@intCast(address)..][0..out.len]);
            return true;
        }

        fn write(context: *anyopaque, address: u64, input: []const u8) bool {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (address + input.len > self.bytes.len) return false;
            @memcpy(self.bytes[@intCast(address)..][0..input.len], input);
            return true;
        }

        fn alloc(_: *anyopaque, _: u64, _: u64) ?u64 {
            return null;
        }
    };

    var harness = Harness{};
    const memory = GuestMemory{
        .context = @ptrCast(&harness),
        .read = Harness.read,
        .write = Harness.write,
        .alloc = Harness.alloc,
    };
    try std.testing.expect(writeInt(memory, 8, @as(u64, 0x1122_3344_5566_7788)));
    try std.testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), readInt(memory, 8, u64).?);
    try std.testing.expectEqual(@as(u8, 0x88), harness.bytes[8]);
}
