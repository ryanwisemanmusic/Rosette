//! Select the architectural register/vector files for the active PE guest
//! context. Native Vulkan dispatch runs on the host thread of whichever guest
//! thread made the call, so reading `state.regs` directly would touch the
//! process owner's register file instead of the caller's - and in parallel
//! mode the owner is running on another core at the same time.

const std = @import("std");
const guest_context = @import("guest_context");

/// Return an architectural field from the currently bound Windows guest
/// context, falling back to the state's normal field for standalone callers
/// and small test doubles.
pub fn field(state: anytype, comptime name: []const u8) guest_context.FieldPointer(@TypeOf(state), name) {
    return guest_context.field(state, name);
}

/// Run the shared dyld Vulkan dispatcher for the calling guest thread.
///
/// The dispatcher reaches every register through `guest_context`, so it
/// already reads the caller's arguments and writes the caller's results in
/// the caller's own context. Nothing is copied.
///
/// This used to install the worker's registers in `state.regs` for the call
/// and restore the owner's afterwards, which was sound only while every guest
/// thread shared one host thread. With workers on their own threads,
/// `state.regs` is the owner's *live* file: on 2026-09-26 Xenia's UI thread
/// ran with the Emulator thread's registers for the length of each of its
/// Vulkan calls, then had its own overwritten with a stale copy, and jumped
/// into the Emulator thread's stack after the third `vkGetDeviceQueue`.
pub fn dispatchWithActiveRegisterFile(forwarder: anytype, state: anytype, token: u64) bool {
    return forwarder.dispatchGuestSymbol(state, token);
}

test "register and vector access follows a bound guest context" {
    const Registers = struct {
        rax: u64 = 0,
        rdx: u64 = 0,
        rip: u64 = 0,
    };
    const Vectors = [16][16]u8;
    const State = struct {
        regs: Registers = .{},
        xmm: Vectors = @splat(@splat(0)),
        context: struct {
            regs: Registers = .{},
            xmm: Vectors = @splat(@splat(0)),
        } = .{},

        pub fn windowsGuestContextField(self: *@This(), comptime name: []const u8) *@FieldType(@This(), name) {
            return &@field(self.context, name);
        }
    };

    var state = State{};
    state.regs.rax = 0xA11CE;
    state.regs.rip = 0x140001000;
    state.context.regs.rax = 0xB0B;
    state.context.regs.rdx = 0x111;
    state.context.regs.rip = 0x140002000;

    field(&state, "regs").*.rax = 7;
    field(&state, "regs").*.rip = 0x140002004;
    field(&state, "xmm").*[3][5] = 0xCC;

    try std.testing.expectEqual(@as(u64, 0xA11CE), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x140001000), state.regs.rip);
    try std.testing.expectEqual(@as(u64, 7), state.context.regs.rax);
    try std.testing.expectEqual(@as(u64, 0x140002004), state.context.regs.rip);
    try std.testing.expectEqual(@as(u8, 0xCC), state.context.xmm[3][5]);
    try std.testing.expectEqual(@as(u8, 0), state.xmm[3][5]);
}

test "shared Vulkan dispatch uses worker arguments and keeps its VkResult in that worker" {
    const Registers = struct {
        rax: u64 = 0,
        rdi: u64 = 0,
        rsi: u64 = 0,
        rdx: u64 = 0,
    };
    const State = struct {
        regs: Registers = .{},
        context: struct { regs: Registers = .{} } = .{},
        mem: [32]u8 = @splat(0),

        pub fn windowsGuestContextField(self: *@This(), comptime name: []const u8) *@FieldType(@This(), name) {
            return &@field(self.context, name);
        }

        pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            const capacity: u64 = @intCast(self.mem.len);
            if (address > capacity or length > capacity - address) return null;
            return self.mem[@intCast(address)..][0..@intCast(length)];
        }

        pub fn write32(self: *@This(), address: u64, value: u32) void {
            const bytes = self.guestMemory(address, 4) orelse return;
            std.mem.writeInt(u32, bytes[0..4], value, .little);
        }
    };
    // Reads and writes registers the way the real dyld forwarder does.
    const FakeForwarder = struct {
        observed_layer_name: u64 = 0,

        pub fn dispatchGuestSymbol(self: *@This(), state: anytype, _: u64) bool {
            self.observed_layer_name = guest_context.registers(state).rdi;
            if (guest_context.registers(state).rdi != 0) {
                guest_context.registers(state).rax = 0xFFFF_FFFA; // VK_ERROR_LAYER_NOT_PRESENT
                return true;
            }
            state.write32(guest_context.registers(state).rsi, 5);
            guest_context.registers(state).rax = 0;
            return true;
        }
    };

    var state = State{};
    state.regs = .{ .rax = 0xA11CE, .rdi = 0x1234, .rsi = 0x5678, .rdx = 0x9ABC };
    state.context.regs = .{ .rax = 0xB0B, .rdi = 0, .rsi = 8, .rdx = 0 };
    const owner_before = state.regs;
    var forwarder = FakeForwarder{};

    try std.testing.expect(dispatchWithActiveRegisterFile(&forwarder, &state, 1));

    try std.testing.expectEqual(@as(u64, 0), forwarder.observed_layer_name);
    try std.testing.expectEqual(@as(u32, 5), std.mem.readInt(u32, state.mem[8..12], .little));
    try std.testing.expectEqual(@as(u64, 0), state.context.regs.rax);
    try std.testing.expectEqualDeep(owner_before, state.regs);
}

test "shared Vulkan dispatch preserves results without a worker-local register file" {
    const State = struct {
        regs: struct { rax: u64 = 0, rdi: u64 = 0, rsi: u64 = 0 } = .{},
        mem: [16]u8 = @splat(0),

        pub fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            const capacity: u64 = @intCast(self.mem.len);
            if (address > capacity or length > capacity - address) return null;
            return self.mem[@intCast(address)..][0..@intCast(length)];
        }

        pub fn write32(self: *@This(), address: u64, value: u32) void {
            const bytes = self.guestMemory(address, 4) orelse return;
            std.mem.writeInt(u32, bytes[0..4], value, .little);
        }
    };
    const FakeForwarder = struct {
        pub fn dispatchGuestSymbol(_: *@This(), state: anytype, _: u64) bool {
            state.write32(guest_context.registers(state).rsi, 5);
            guest_context.registers(state).rax = 0xFFFF_FFFA;
            return true;
        }
    };

    var state = State{};
    state.regs = .{ .rax = 0xA11CE, .rdi = 0, .rsi = 8 };
    var forwarder = FakeForwarder{};
    try std.testing.expect(dispatchWithActiveRegisterFile(&forwarder, &state, 1));
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFA), state.regs.rax);
    try std.testing.expectEqual(@as(u32, 5), std.mem.readInt(u32, state.mem[8..12], .little));
}

test "a worker's Vulkan dispatch never touches the owner's live registers" {
    // The 2026-09-26 shape: the owner (Xenia's UI thread) keeps executing on
    // its own host thread while a worker (the Emulator thread) makes Vulkan
    // calls on another. The owner writes its registers and checks them back
    // the way an instruction stream would; a dispatch that borrowed the
    // owner's file for its call shows up as a value the owner never wrote.
    const Registers = struct {
        rax: u64 = 0,
        rdi: u64 = 0,
        rsp: u64 = 0,
        rip: u64 = 0,
    };
    const State = struct {
        regs: Registers = .{},

        const Context = struct { regs: Registers = .{} };
        threadlocal var bound: ?*Context = null;

        pub fn windowsGuestContextField(self: *@This(), comptime name: []const u8) *@FieldType(Context, name) {
            if (bound) |context| return &@field(context.*, name);
            return &@field(self.*, name);
        }
    };
    const Forwarder = struct {
        pub fn dispatchGuestSymbol(_: *@This(), state: anytype, _: u64) bool {
            // Arguments in, a result out, with a little work in between
            // so the call spans a real window of the owner's execution.
            const argument = guest_context.registers(state).rdi;
            var spin: u32 = 0;
            while (spin < 64) : (spin += 1) std.atomic.spinLoopHint();
            guest_context.registers(state).rax = argument ^ 0x5A5A;
            return true;
        }
    };
    const Shared = struct {
        state: State = .{},
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        owner_saw_foreign: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        worker_saw_wrong_result: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        fn owner(self: *@This()) void {
            var value: u64 = 0x140000000;
            while (!self.stop.load(.acquire)) : (value +%= 4) {
                const rip: *volatile u64 = &self.state.regs.rip;
                const rsp: *volatile u64 = &self.state.regs.rsp;
                rip.* = value;
                rsp.* = value ^ 0xFFFF;
                std.atomic.spinLoopHint();
                if (rip.* != value or rsp.* != value ^ 0xFFFF) _ = self.owner_saw_foreign.fetchAdd(1, .monotonic);
            }
        }

        fn worker(self: *@This()) void {
            var context: State.Context = .{ .regs = .{ .rsp = 0x1443c4190, .rip = 0xfffffb0000000671 } };
            State.bound = &context;
            defer State.bound = null;
            var forwarder: Forwarder = .{};
            for (0..20_000) |iteration| {
                context.regs.rdi = iteration;
                _ = dispatchWithActiveRegisterFile(&forwarder, &self.state, 1);
                if (context.regs.rax != iteration ^ 0x5A5A) _ = self.worker_saw_wrong_result.fetchAdd(1, .monotonic);
            }
        }
    };
    var shared: Shared = .{};
    const owner_thread = try std.Thread.spawn(.{}, Shared.owner, .{&shared});
    const worker_thread = try std.Thread.spawn(.{}, Shared.worker, .{&shared});
    worker_thread.join();
    shared.stop.store(true, .release);
    owner_thread.join();
    try std.testing.expectEqual(@as(u64, 0), shared.owner_saw_foreign.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), shared.worker_saw_wrong_result.load(.acquire));
    // The owner's file never held a worker value.
    try std.testing.expect(shared.state.regs.rdi == 0 and shared.state.regs.rax == 0);
}
