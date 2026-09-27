//! The guest thread a host thread is executing, for code that runs on its
//! behalf.
//!
//! Rosette runs guest threads on several host threads at once. The state an
//! import handler, a shim or the Vulkan forwarder is handed is the *process*:
//! its `regs`, `xmm` and the other architectural fields are the live
//! registers of the process owner - the thread that entered the image, which
//! for Xenia is its UI thread. When a worker's host thread runs that code on
//! its own guest thread's behalf, `state.regs` is somebody else's register
//! file, and that somebody is running on another core at the same moment.
//!
//! So code that runs on a guest thread's behalf reaches architectural and
//! execution-local state through this module, never through the field. A
//! state that runs more than one guest context declares
//! `windowsGuestContextField(comptime name)`, which returns the field of the
//! context bound to the calling host thread; for every other state the field
//! itself is the only context there is, and this module returns it.
//!
//! See README.md for the rule, the run that made it one, and the audit that
//! keeps it.

const std = @import("std");

/// The pointer `field` returns for `name`: to that field's type, and const
/// exactly when the state pointer is.
pub fn FieldPointer(comptime StatePointer: type, comptime name: []const u8) type {
    const info = @typeInfo(StatePointer).pointer;
    const Value = @FieldType(info.child, name);
    return if (info.is_const) *const Value else *Value;
}

/// Whether a state type runs more than one guest context, and so selects
/// execution-local fields by the calling host thread.
pub fn runsSeveralContexts(comptime State: type) bool {
    return @hasDecl(State, "windowsGuestContextField");
}

/// The executing guest context's `name` field.
pub fn field(state: anytype, comptime name: []const u8) FieldPointer(@TypeOf(state), name) {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (comptime runsSeveralContexts(State)) return state.windowsGuestContextField(name);
    return &@field(state.*, name);
}

/// The executing guest context's general-purpose register file.
pub fn registers(state: anytype) FieldPointer(@TypeOf(state), "regs") {
    return field(state, "regs");
}

/// The executing guest context's XMM register file.
pub fn vectors(state: anytype) FieldPointer(@TypeOf(state), "xmm") {
    return field(state, "xmm");
}

const TestRegisters = struct {
    rax: u64 = 0,
    rdi: u64 = 0,
    rip: u64 = 0,
};

/// A stand-in for the PE state: its own fields are the owner's context, and
/// a host thread that has bound a context sees that context instead.
const SeveralContexts = struct {
    regs: TestRegisters = .{},
    xmm: [16][16]u8 = @splat(@splat(0)),

    const Context = struct {
        regs: TestRegisters = .{},
        xmm: [16][16]u8 = @splat(@splat(0)),
    };

    threadlocal var bound: ?*Context = null;

    pub fn windowsGuestContextField(
        self: anytype,
        comptime name: []const u8,
    ) if (@typeInfo(@TypeOf(self)).pointer.is_const)
        *const @FieldType(Context, name)
    else
        *@FieldType(Context, name) {
        if (bound) |context| return &@field(context.*, name);
        return &@field(self.*, name);
    }
};

test "a state with one context is its own executing context" {
    const Single = struct { regs: TestRegisters = .{}, xmm: [16][16]u8 = @splat(@splat(0)) };
    var state: Single = .{};
    registers(&state).rax = 7;
    vectors(&state)[2][3] = 0xAB;
    try std.testing.expectEqual(@as(u64, 7), state.regs.rax);
    try std.testing.expectEqual(@as(u8, 0xAB), state.xmm[2][3]);
    const read_only: *const Single = &state;
    try std.testing.expectEqual(@as(u64, 7), registers(read_only).rax);
    try std.testing.expect(!runsSeveralContexts(Single));
}

test "a bound context is what the calling host thread executes" {
    var state: SeveralContexts = .{};
    state.regs.rax = 0x0A11CE;
    var context: SeveralContexts.Context = .{};
    SeveralContexts.bound = &context;
    defer SeveralContexts.bound = null;
    registers(&state).rax = 0xB0B;
    vectors(&state)[1][0] = 0xCC;
    try std.testing.expectEqual(@as(u64, 0x0A11CE), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 0xB0B), context.regs.rax);
    try std.testing.expectEqual(@as(u8, 0), state.xmm[1][0]);
    try std.testing.expectEqual(@as(u8, 0xCC), context.xmm[1][0]);
    const read_only: *const SeveralContexts = &state;
    try std.testing.expectEqual(@as(u64, 0xB0B), registers(read_only).rax);
    try std.testing.expect(runsSeveralContexts(SeveralContexts));
}

test "workers on their own host threads never touch the owner's live registers" {
    // The owner keeps writing and re-reading its own register file while
    // workers run calls that read their arguments and write their results
    // through this module. Any worker access to the owner's file shows up as
    // a value the owner did not write.
    const Shared = struct {
        state: SeveralContexts = .{},
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        foreign_values: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        fn owner(self: *@This()) void {
            var value: u64 = 1;
            while (!self.stop.load(.acquire)) : (value +%= 1) {
                // Plain accesses, as the interpreter makes them. A worker
                // writing this file would race them; the check below is what
                // would see it.
                const regs = registers(&self.state);
                @as(*volatile u64, &regs.rax).* = value;
                @as(*volatile u64, &regs.rip).* = value;
                if (@as(*volatile u64, &regs.rax).* != value or @as(*volatile u64, &regs.rip).* != value) {
                    _ = self.foreign_values.fetchAdd(1, .monotonic);
                }
            }
        }

        fn worker(self: *@This(), seed: u64) void {
            var context: SeveralContexts.Context = .{};
            SeveralContexts.bound = &context;
            defer SeveralContexts.bound = null;
            for (0..20_000) |iteration| {
                const argument = seed * 1_000_000 + iteration;
                registers(&self.state).rdi = argument;
                // The "call": read the argument, write the result.
                registers(&self.state).rax = registers(&self.state).rdi *% 3;
                if (registers(&self.state).rax != argument *% 3) {
                    _ = self.foreign_values.fetchAdd(1, .monotonic);
                }
            }
        }
    };
    var shared: Shared = .{};
    const owner_thread = try std.Thread.spawn(.{}, Shared.owner, .{&shared});
    var workers: [3]std.Thread = undefined;
    for (&workers, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Shared.worker, .{ &shared, index + 1 });
    for (workers) |thread| thread.join();
    shared.stop.store(true, .release);
    owner_thread.join();
    try std.testing.expectEqual(@as(u64, 0), shared.foreign_values.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), shared.state.regs.rdi);
}
