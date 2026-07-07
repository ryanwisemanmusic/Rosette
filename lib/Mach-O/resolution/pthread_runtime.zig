const std = @import("std");

const CURRENT_THREAD_HANDLE: u64 = 0x7FFF_1000;
const SYNTHETIC_THREAD_BASE: u64 = 0x7FFF_2000;
const MAX_ATTRIBUTES = 32;
const MAX_THREADS = 64;
const MAX_MUTEXES = 128;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const Attribute = struct {
    active: bool = false,
    address: u64 = 0,
    stack_size: u64 = 0,
};

pub const DeferredThread = struct {
    handle: u64,
    start_routine: u64,
    argument: u64,
    stack_size: u64,
};

const Thread = struct {
    active: bool = false,
    handle: u64 = 0,
    start_routine: u64 = 0,
    argument: u64 = 0,
    stack_size: u64 = 0,
    joined: bool = false,
    cancelled: bool = false,
    started: bool = false,
    completed: bool = false,
};

const Mutex = struct {
    active: bool = false,
    address: u64 = 0,
    depth: u32 = 0,
};

pub const Runtime = struct {
    attributes: [MAX_ATTRIBUTES]Attribute = [_]Attribute{.{}} ** MAX_ATTRIBUTES,
    threads: [MAX_THREADS]Thread = [_]Thread{.{}} ** MAX_THREADS,
    mutexes: [MAX_MUTEXES]Mutex = [_]Mutex{.{}} ** MAX_MUTEXES,
    created_threads: u64 = 0,
    deferred_threads: u64 = 0,
    joined_threads: u64 = 0,
    cancelled_threads: u64 = 0,
    mutex_locks: u64 = 0,
    mutex_unlocks: u64 = 0,
    collapsed_waits: u64 = 0,
    condition_notifications: u64 = 0,
    tls_sets: u64 = 0,
    scheduled_threads: u64 = 0,
    completed_threads: u64 = 0,

    pub fn dispatch(self: *Runtime, state: anytype, name: []const u8) ?Outcome {
        if (std.mem.eql(u8, name, "_pthread_self")) return .{ .handled = CURRENT_THREAD_HANDLE };
        if (std.mem.eql(u8, name, "_pthread_equal")) return .{ .handled = @intFromBool(state.regs.rdi == state.regs.rsi) };
        if (std.mem.eql(u8, name, "_pthread_threadid_np")) return .{ .handled = self.threadId(state) };
        if (std.mem.eql(u8, name, "_pthread_attr_init")) return .{ .handled = self.attributeInit(state) };
        if (std.mem.eql(u8, name, "_pthread_attr_destroy")) return .{ .handled = self.attributeDestroy(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_attr_setstacksize")) return .{ .handled = self.attributeSetStackSize(state.regs.rdi, state.regs.rsi) };
        if (std.mem.eql(u8, name, "_pthread_create")) return .{ .handled = self.create(state) };
        if (std.mem.eql(u8, name, "_pthread_join")) return .{ .handled = self.join(state) };
        if (std.mem.eql(u8, name, "_pthread_cancel")) return .{ .handled = self.cancel(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_setname_np") or
            std.mem.eql(u8, name, "_pthread_setschedparam") or
            std.mem.eql(u8, name, "_pthread_yield_np")) return .{ .handled = 0 };
        if (std.mem.eql(u8, name, "_pthread_getname_np")) return .{ .handled = self.getName(state) };
        if (std.mem.eql(u8, name, "_pthread_getschedparam")) return .{ .handled = self.getSchedule(state) };
        if (std.mem.eql(u8, name, "_pthread_getspecific")) return .{ .handled = 0 };
        if (std.mem.eql(u8, name, "_pthread_setspecific")) {
            self.tls_sets +|= 1;
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_mutex_init")) return .{ .handled = self.mutexInit(state) };
        if (std.mem.eql(u8, name, "_pthread_mutex_destroy")) return .{ .handled = self.mutexDestroy(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_mutex_lock")) return .{ .handled = self.mutexLock(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_mutex_unlock")) return .{ .handled = self.mutexUnlock(state.regs.rdi) };
        if (std.mem.eql(u8, name, "_pthread_cond_init")) return .{ .handled = initializeOpaque(state, state.regs.rdi, 48) };
        if (std.mem.eql(u8, name, "_pthread_cond_destroy")) return .{ .handled = 0 };
        if (std.mem.eql(u8, name, "_pthread_cond_signal") or std.mem.eql(u8, name, "_pthread_cond_broadcast")) {
            self.condition_notifications +|= 1;
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_pthread_cond_wait")) {
            self.collapsed_waits +|= 1;
            if (self.collapsed_waits <= 8 or self.collapsed_waits % 1000 == 0) {
                std.debug.print(
                    "macho-processor: pthread runtime: collapsed condition wait #{d} cond=0x{x} mutex=0x{x} (single guest execution thread)\n",
                    .{ self.collapsed_waits, state.regs.rdi, state.regs.rsi },
                );
            }
            return .{ .handled = 0 };
        }
        return null;
    }

    pub fn logSummary(self: *const Runtime) void {
        if (self.created_threads == 0 and self.mutex_locks == 0 and self.collapsed_waits == 0 and self.tls_sets == 0) return;
        std.debug.print(
            "macho-processor: pthread runtime: created={d} deferred={d} scheduled={d} completed={d} joined={d} cancelled={d} mutex(lock/unlock)={d}/{d} cond_notify={d} waits_collapsed={d} tls_sets={d}\n",
            .{
                self.created_threads,
                self.deferred_threads,
                self.scheduled_threads,
                self.completed_threads,
                self.joined_threads,
                self.cancelled_threads,
                self.mutex_locks,
                self.mutex_unlocks,
                self.condition_notifications,
                self.collapsed_waits,
                self.tls_sets,
            },
        );
    }

    pub fn takeNewestDeferred(self: *Runtime) ?DeferredThread {
        var index = self.threads.len;
        while (index != 0) {
            index -= 1;
            const thread = &self.threads[index];
            if (!thread.active or thread.started or thread.cancelled) continue;
            thread.started = true;
            self.deferred_threads -|= 1;
            self.scheduled_threads +|= 1;
            return .{
                .handle = thread.handle,
                .start_routine = thread.start_routine,
                .argument = thread.argument,
                .stack_size = thread.stack_size,
            };
        }
        return null;
    }

    pub fn markCompleted(self: *Runtime, handle: u64) void {
        const thread = self.threadForHandle(handle) orelse return;
        if (thread.completed) return;
        thread.completed = true;
        self.completed_threads +|= 1;
    }

    fn attributeInit(self: *Runtime, state: anytype) u64 {
        if (initializeOpaque(state, state.regs.rdi, 64) != 0) return 22;
        for (&self.attributes) |*attribute| {
            if (attribute.active) continue;
            attribute.* = .{ .active = true, .address = state.regs.rdi };
            return 0;
        }
        return 12;
    }

    fn attributeDestroy(self: *Runtime, address: u64) u64 {
        for (&self.attributes) |*attribute| {
            if (!attribute.active or attribute.address != address) continue;
            attribute.* = .{};
            return 0;
        }
        return 0;
    }

    fn attributeSetStackSize(self: *Runtime, address: u64, stack_size: u64) u64 {
        for (&self.attributes) |*attribute| {
            if (!attribute.active or attribute.address != address) continue;
            attribute.stack_size = stack_size;
            return 0;
        }
        return 22;
    }

    fn create(self: *Runtime, state: anytype) u64 {
        if (state.guestMemory(state.regs.rdi, 8) == null) return 14;
        for (&self.threads, 0..) |*thread, index| {
            if (thread.active) continue;
            const handle = SYNTHETIC_THREAD_BASE + @as(u64, @intCast(index)) * 0x10;
            thread.* = .{
                .active = true,
                .handle = handle,
                .start_routine = state.regs.rdx,
                .argument = state.regs.rcx,
                .stack_size = self.stackSize(state.regs.rsi),
            };
            state.write64(state.regs.rdi, handle);
            self.created_threads +|= 1;
            self.deferred_threads +|= 1;
            std.debug.print(
                "macho-processor: pthread runtime: deferred guest thread #{d} handle=0x{x} start=0x{x} arg=0x{x} stack={d}\n",
                .{ self.created_threads, handle, thread.start_routine, thread.argument, thread.stack_size },
            );
            return 0;
        }
        return 11;
    }

    fn join(self: *Runtime, state: anytype) u64 {
        const thread = self.threadForHandle(state.regs.rdi) orelse return 3;
        thread.joined = true;
        self.joined_threads +|= 1;
        if (state.regs.rsi != 0 and state.guestMemory(state.regs.rsi, 8) != null) state.write64(state.regs.rsi, 0);
        return 0;
    }

    fn cancel(self: *Runtime, handle: u64) u64 {
        const thread = self.threadForHandle(handle) orelse return 3;
        thread.cancelled = true;
        self.cancelled_threads +|= 1;
        return 0;
    }

    fn mutexInit(self: *Runtime, state: anytype) u64 {
        if (initializeOpaque(state, state.regs.rdi, 64) != 0) return 22;
        _ = self.mutexForAddress(state.regs.rdi, true) orelse return 12;
        return 0;
    }

    fn mutexDestroy(self: *Runtime, address: u64) u64 {
        if (self.mutexForAddress(address, false)) |mutex| mutex.* = .{};
        return 0;
    }

    fn mutexLock(self: *Runtime, address: u64) u64 {
        const mutex = self.mutexForAddress(address, true) orelse return 12;
        mutex.depth +|= 1;
        self.mutex_locks +|= 1;
        return 0;
    }

    fn mutexUnlock(self: *Runtime, address: u64) u64 {
        const mutex = self.mutexForAddress(address, false) orelse return 22;
        if (mutex.depth != 0) mutex.depth -= 1;
        self.mutex_unlocks +|= 1;
        return 0;
    }

    fn threadId(self: *Runtime, state: anytype) u64 {
        _ = self;
        if (state.regs.rsi == 0 or state.guestMemory(state.regs.rsi, 8) == null) return 22;
        state.write64(state.regs.rsi, if (state.regs.rdi == 0 or state.regs.rdi == CURRENT_THREAD_HANDLE) 1 else state.regs.rdi & 0xFFFF);
        return 0;
    }

    fn getName(self: *Runtime, state: anytype) u64 {
        _ = self;
        if (state.regs.rdx == 0) return 22;
        const storage = state.guestMemory(state.regs.rsi, state.regs.rdx) orelse return 14;
        const name = "rosette-guest";
        const length = @min(name.len, storage.len - 1);
        @memcpy(storage[0..length], name[0..length]);
        storage[length] = 0;
        return 0;
    }

    fn getSchedule(self: *Runtime, state: anytype) u64 {
        _ = self;
        if (state.regs.rsi != 0 and state.guestMemory(state.regs.rsi, 4) != null) state.write32(state.regs.rsi, 0);
        if (state.regs.rdx != 0 and state.guestMemory(state.regs.rdx, 8) != null) state.write64(state.regs.rdx, 0);
        return 0;
    }

    fn stackSize(self: *const Runtime, attribute_address: u64) u64 {
        if (attribute_address == 0) return 0;
        for (self.attributes) |attribute| {
            if (attribute.active and attribute.address == attribute_address) return attribute.stack_size;
        }
        return 0;
    }

    fn threadForHandle(self: *Runtime, handle: u64) ?*Thread {
        for (&self.threads) |*thread| {
            if (thread.active and thread.handle == handle) return thread;
        }
        return null;
    }

    fn mutexForAddress(self: *Runtime, address: u64, create_if_missing: bool) ?*Mutex {
        for (&self.mutexes) |*mutex| {
            if (mutex.active and mutex.address == address) return mutex;
        }
        if (!create_if_missing) return null;
        for (&self.mutexes) |*mutex| {
            if (mutex.active) continue;
            mutex.* = .{ .active = true, .address = address };
            return mutex;
        }
        return null;
    }
};

fn initializeOpaque(state: anytype, address: u64, size: u64) u64 {
    const storage = state.guestMemory(address, size) orelse return 14;
    @memset(storage, 0);
    return 0;
}

test "pthread runtime records deferred guest threads" {
    const TestState = struct {
        memory: [256]u8 = [_]u8{0} ** 256,
        regs: struct { rdi: u64 = 0, rsi: u64 = 0, rdx: u64 = 0, rcx: u64 = 0 } = .{},

        fn guestMemory(self: *@This(), address: u64, length: u64) ?[]u8 {
            if (address + length > self.memory.len) return null;
            return self.memory[@intCast(address)..@intCast(address + length)];
        }

        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.memory[@intCast(address)..][0..8], value, .little);
        }

        fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.memory[@intCast(address)..][0..4], value, .little);
        }
    };

    var runtime = Runtime{};
    var state = TestState{};
    state.regs.rdi = 16;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_attr_init").?.handled);
    state.regs.rsi = 4 * 1024 * 1024;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_attr_setstacksize").?.handled);
    state.regs.rdi = 8;
    state.regs.rsi = 16;
    state.regs.rdx = 0x1234;
    state.regs.rcx = 0x5678;
    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_pthread_create").?.handled);
    try std.testing.expectEqual(@as(u64, 1), runtime.deferred_threads);
    try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), runtime.threads[0].stack_size);
    const deferred = runtime.takeNewestDeferred().?;
    try std.testing.expectEqual(@as(u64, 0x1234), deferred.start_routine);
    try std.testing.expectEqual(@as(u64, 0x5678), deferred.argument);
    try std.testing.expectEqual(@as(u64, 0), runtime.deferred_threads);
    runtime.markCompleted(deferred.handle);
    try std.testing.expectEqual(@as(u64, 1), runtime.completed_threads);
}
