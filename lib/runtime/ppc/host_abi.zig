//! The C ABI a PowerPC host embedder calls into.
//!
//! This is the Rosette half of the contract in Xenia's
//! `src/xenia/cpu/backend/ppc/rosette_ppc_bridge.h`. The embedder owns the
//! guest address space, the kernel export table, and the module loader; Rosette
//! owns instruction decode and execution. Neither side reaches into the other's
//! half - the seam is these six functions and five callbacks.
//!
//! Register state is copied in at the start of an execution request and out
//! again at every point the embedder can observe it - a system call, a call
//! into a host function, a fault, and the return. That is a deliberate trade:
//! the hot interpreter loop works on a compact local register file rather than
//! chasing thirteen pointers into the embedder's context, and the copy happens
//! per *call boundary* rather than per instruction. Skipping the sync at a
//! callback would be the expensive kind of wrong - a kernel export would read
//! stale arguments and write results the guest never sees.
//!
//! The call classifier is the other load-bearing piece. Rosette cannot tell an
//! import thunk from ordinary guest code: both are real PowerPC in the title's
//! image, and interpreting the thunk instead of calling the host's shim would
//! run the original bytes and silently skip the kernel. So every taken control
//! transfer is classified once by the embedder and the *guest-code* verdict is
//! cached; a host verdict is never cached, because "the embedder handled it"
//! means it ran something and has to run it again next time.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const state_mod = @import("state.zig");
const memory_mod = @import("memory.zig");
const context_mod = @import("context.zig");
const execute_mod = @import("execute.zig");
const jit_mod = @import("jit/root.zig");

const State = state_mod.State;
const Memory = memory_mod.Memory;
const Context = context_mod.Context;

/// Bumped whenever `GuestState` changes shape. An embedder built against an
/// older layout is refused rather than read through moved fields.
pub const abi_version: u32 = 1;

pub const identity = "Rosette direct PowerPC host (ISA/ppc + lib/runtime/ppc)";

/// What the embedder decided about a control transfer.
pub const CallStatus = enum(i32) {
    /// The embedder ran it. Guest registers already hold the result.
    handled = 0,
    /// Ordinary guest PowerPC. Keep interpreting.
    is_guest_code = 1,
    /// Nothing is there.
    unresolved = 2,
};

/// Why an execution request returned.
pub const RunStatus = enum(i32) {
    returned = 0,
    terminated = 1,
    unimplemented = 2,
    illegal = 3,
    memory_fault = 4,
    refused = 5,
};

/// Mirrors `RosettePpcGuestState`. Field order and types are the contract.
pub const GuestState = extern struct {
    abi_version: u32,
    reserved: u32,

    gpr: [*]u64,
    fpr: [*]f64,
    /// 128 entries of four host-order u32, AltiVec element 0 first.
    vr: [*][4]u32,
    lr: *u64,
    ctr: *u64,
    msr: *u64,
    fpscr: *u32,
    xer_ca: *u8,
    xer_ov: *u8,
    xer_so: *u8,
    vscr_sat: *u8,
    vrsave: *u32,
    reserved_val: *u64,

    virtual_membase: [*]u8,
    guest_address_space_size: u64,

    host_context: *anyopaque,

    read_cr: *const fn (*anyopaque) callconv(.c) u32,
    write_cr: *const fn (*anyopaque, u32) callconv(.c) void,
    system_call: *const fn (*anyopaque, u32, u32) callconv(.c) i32,
    resolve_call: *const fn (*anyopaque, u32, u32) callconv(.c) i32,
    trap: *const fn (*anyopaque, u32) callconv(.c) void,
};

/// Mirrors `RosettePpcRunResult`.
pub const RunResult = extern struct {
    status: i32,
    address: u32,
    instructions_retired: u64,
    unimplemented_opcode: ?[*:0]const u8,
};

/// A direct-mapped cache of "this target address is ordinary guest code".
///
/// Only the guest-code verdict is cached. Caching the host verdict would turn
/// the second call to a kernel export into a no-op that skips the export.
const CallCache = struct {
    const size = 4096;
    const empty: u32 = 0;

    entries: [size]u32 = [_]u32{empty} ** size,

    fn slot(address: u32) usize {
        // Guest instruction addresses are four-byte aligned, so the low two
        // bits carry no information and hashing on them would waste 3/4 of the
        // table.
        return (address >> 2) % size;
    }

    fn knownGuestCode(self: *const CallCache, address: u32) bool {
        return address != empty and self.entries[slot(address)] == address;
    }

    fn noteGuestCode(self: *CallCache, address: u32) void {
        if (address == empty) return;
        self.entries[slot(address)] = address;
    }

    fn invalidate(self: *CallCache, low: u32, high: u32) void {
        for (&self.entries) |*entry| {
            if (entry.* >= low and entry.* < high) entry.* = empty;
        }
    }

    fn clear(self: *CallCache) void {
        @memset(&self.entries, empty);
    }
};

/// One bound guest thread.
const Binding = struct {
    used: bool = false,
    guest: GuestState = undefined,
    state: State = .{},
    calls: CallCache = .{},
    /// The recompiler, when this host can allocate executable memory and the
    /// embedder has not turned it off. A null one is not an error: the
    /// interpreter is the complete implementation and the recompiler is a
    /// throughput optimisation over it.
    jit: ?jit_mod.Jit = null,
};

/// Whether newly bound threads get a recompiler. Off until an embedder asks:
/// a JIT that starts itself changes the timing of every run, including the ones
/// being used to diagnose something else.
var jit_enabled: bool = false;
/// Code cache size per guest thread.
var jit_capacity: usize = 4 * 1024 * 1024;

/// Xbox 360 titles run a bounded number of guest threads; the kernel's own
/// limit is well under this. A fixed table keeps binding lock-free on the hot
/// path and avoids an allocator on a boundary that must work during teardown.
const max_bindings = 64;

/// Binding and release happen at guest-thread creation and teardown, not on
/// the execution path, so a spin lock is the right weight here: it needs no
/// allocator, no Io instance, and no teardown of its own - all three of which
/// matter on a boundary that has to keep working while the process is exiting.
const SpinLock = struct {
    held: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn lock(self: *SpinLock) void {
        while (self.held.swap(true, .acquire)) std.atomic.spinLoopHint();
    }

    fn unlock(self: *SpinLock) void {
        self.held.store(false, .release);
    }
};

var bindings: [max_bindings]Binding = [_]Binding{.{}} ** max_bindings;
var bindings_lock: SpinLock = .{};

fn findBinding(host_context: *anyopaque) ?*Binding {
    for (&bindings) |*binding| {
        if (binding.used and binding.guest.host_context == host_context) return binding;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Register sync
//
// The embedder's context is authoritative between calls; the local State is
// authoritative during one. Every transition between those two facts goes
// through exactly one of these two functions.
// ---------------------------------------------------------------------------

fn syncFromGuest(binding: *Binding) void {
    const g = &binding.guest;
    const s = &binding.state;
    @memcpy(s.gpr[0..32], g.gpr[0..32]);
    @memcpy(s.fpr[0..32], g.fpr[0..32]);
    @memcpy(s.vr[0..128], g.vr[0..128]);
    s.lr = g.lr.*;
    s.ctr = g.ctr.*;
    s.msr = g.msr.*;
    s.fpscr = g.fpscr.*;
    s.xer.ca = g.xer_ca.* != 0;
    s.xer.ov = g.xer_ov.* != 0;
    s.xer.so = g.xer_so.* != 0;
    s.vscr = if (g.vscr_sat.* != 0) 1 else 0;
    s.cr = g.read_cr(g.host_context);
}

fn syncToGuest(binding: *Binding) void {
    const g = &binding.guest;
    const s = &binding.state;
    @memcpy(g.gpr[0..32], s.gpr[0..32]);
    @memcpy(g.fpr[0..32], s.fpr[0..32]);
    @memcpy(g.vr[0..128], s.vr[0..128]);
    g.lr.* = s.lr;
    g.ctr.* = s.ctr;
    g.msr.* = s.msr;
    g.fpscr.* = s.fpscr;
    g.xer_ca.* = @intFromBool(s.xer.ca);
    g.xer_ov.* = @intFromBool(s.xer.ov);
    g.xer_so.* = @intFromBool(s.xer.so);
    g.vscr_sat.* = @intFromBool(s.vscr & 1 != 0);
    g.write_cr(g.host_context, s.cr);
}

fn memoryFor(binding: *const Binding) Memory {
    const size: usize = @intCast(@min(
        binding.guest.guest_address_space_size,
        @as(u64, std.math.maxInt(u32)) + 1,
    ));
    return .{ .base = binding.guest.virtual_membase, .len = size, .origin = 0 };
}

// ---------------------------------------------------------------------------
// Exported entry points
// ---------------------------------------------------------------------------

pub export fn rosette_ppc_host_available() callconv(.c) i32 {
    return 1;
}

pub export fn rosette_ppc_host_identity() callconv(.c) [*:0]const u8 {
    return identity;
}

pub export fn rosette_ppc_bind_context(guest: *const GuestState) callconv(.c) i32 {
    if (guest.abi_version != abi_version) return 0;

    bindings_lock.lock();
    defer bindings_lock.unlock();

    if (findBinding(guest.host_context)) |existing| {
        existing.guest = guest.*;
        return 1;
    }
    for (&bindings) |*binding| {
        if (!binding.used) {
            binding.* = .{ .used = true, .guest = guest.*, .state = .{}, .calls = .{} };
            if (jit_enabled) {
                binding.jit = jit_mod.Jit.init(
                    std.heap.page_allocator,
                    jit_capacity,
                ) catch null;
            }
            return 1;
        }
    }
    // Refusing is the right answer: silently reusing another thread's binding
    // would give two guest threads one register file.
    return 0;
}

pub export fn rosette_ppc_release_context(host_context: *anyopaque) callconv(.c) void {
    bindings_lock.lock();
    defer bindings_lock.unlock();
    if (findBinding(host_context)) |binding| {
        if (binding.jit) |*j| j.deinit();
        binding.jit = null;
        binding.used = false;
    }
}

/// Turn the recompiler on or off for threads bound after this call. Returns
/// whether the host can run one at all.
pub export fn rosette_ppc_set_recompiler_enabled(enabled: i32) callconv(.c) i32 {
    if (!jit_mod.Jit.available()) return 0;
    jit_enabled = enabled != 0;
    return 1;
}

/// Recompiler counters for a bound thread, for the embedder's run summary.
pub export fn rosette_ppc_recompiler_stats(
    host_context: *anyopaque,
    out_blocks: *u64,
    out_instructions: *u64,
) callconv(.c) i32 {
    bindings_lock.lock();
    defer bindings_lock.unlock();
    const binding = findBinding(host_context) orelse return 0;
    const j = &(binding.jit orelse return 0);
    out_blocks.* = j.stats.blocks_executed;
    out_instructions.* = j.stats.instructions_executed;
    return 1;
}

pub export fn rosette_ppc_invalidate_range(guest_low: u32, guest_high: u32) callconv(.c) void {
    bindings_lock.lock();
    defer bindings_lock.unlock();
    for (&bindings) |*binding| {
        if (!binding.used) continue;
        binding.calls.invalidate(guest_low, guest_high);
        // Compiled code for the range is now stale in exactly the way that
        // matters: it would execute the previous contents of those addresses.
        if (binding.jit) |*j| j.invalidate(guest_low, guest_high);
    }
}

pub export fn rosette_ppc_execute(
    host_context: *anyopaque,
    address: u32,
    return_address: u32,
    out_result: *RunResult,
) callconv(.c) void {
    out_result.* = .{
        .status = @intFromEnum(RunStatus.refused),
        .address = address,
        .instructions_retired = 0,
        .unimplemented_opcode = null,
    };

    const binding = blk: {
        bindings_lock.lock();
        defer bindings_lock.unlock();
        break :blk findBinding(host_context) orelse return;
    };

    runBound(binding, address, return_address, out_result);
}

/// Run one execution request against an already-bound thread.
fn runBound(
    binding: *Binding,
    address: u32,
    return_address: u32,
    out_result: *RunResult,
) void {
    syncFromGuest(binding);
    binding.state.pc = address;
    const retired_at_entry = binding.state.instructions_retired;

    var ctx = Context.init(&binding.state, memoryFor(binding));
    const g = &binding.guest;

    while (true) {
        if (binding.state.pc == return_address) {
            finish(binding, out_result, .returned, binding.state.pc, retired_at_entry, null);
            return;
        }

        // A compiled block first, when one covers this address. It runs the
        // same architected state changes the interpreter would, so the loop
        // below picks up wherever it stopped.
        if (binding.jit) |*j| {
            if (runCompiledBlock(binding, j, out_result, retired_at_entry, return_address)) |handled| {
                if (handled) return;
                continue;
            }
        }

        const at = binding.state.pc;
        const outcome = execute_mod.step(&ctx) catch {
            finish(binding, out_result, .memory_fault, at, retired_at_entry, null);
            return;
        };

        switch (outcome) {
            .advance => {
                // `icbi` is the guest saying the instructions at an address
                // changed. Draining it here, rather than inside the executor,
                // keeps the interpreter unaware of whether a recompiler exists.
                if (binding.state.pending_icache_invalidation) |changed| {
                    binding.state.pending_icache_invalidation = null;
                    if (binding.jit) |*j| {
                        j.invalidate(changed & ~@as(u32, 127), (changed | 127) +% 1);
                    }
                }
            },

            .branch => |target| {
                if (target == return_address) {
                    finish(binding, out_result, .returned, target, retired_at_entry, null);
                    return;
                }
                if (binding.calls.knownGuestCode(target)) continue;

                // The embedder gets the current register state before it looks
                // at the target, because resolving may mean *running* it.
                syncToGuest(binding);
                const verdict: CallStatus = @enumFromInt(
                    g.resolve_call(g.host_context, target, @truncate(binding.state.lr)),
                );
                switch (verdict) {
                    .is_guest_code => {
                        binding.calls.noteGuestCode(target);
                        // Nothing was executed, so the local state is still
                        // current; no reload needed.
                    },
                    .handled => {
                        // The embedder ran a host function against its own
                        // context. Pick the result back up and resume where the
                        // call would have returned to, which is LR for both a
                        // `bl` and a tail-call `b`.
                        syncFromGuest(binding);
                        const resume_at: u32 = @truncate(binding.state.lr & ~@as(u64, 3));
                        binding.state.pc = resume_at;
                        if (resume_at == return_address) {
                            finish(binding, out_result, .returned, resume_at, retired_at_entry, null);
                            return;
                        }
                    },
                    .unresolved => {
                        finish(binding, out_result, .illegal, target, retired_at_entry, null);
                        return;
                    },
                }
            },

            .system_call => |lev| {
                syncToGuest(binding);
                const verdict: CallStatus = @enumFromInt(
                    g.system_call(g.host_context, lev, at),
                );
                if (verdict != .handled) {
                    finish(binding, out_result, .illegal, at, retired_at_entry, null);
                    return;
                }
                syncFromGuest(binding);
                binding.state.pc = at +% 4;
            },

            .trap => {
                syncToGuest(binding);
                g.trap(g.host_context, at);
                syncFromGuest(binding);
                binding.state.pc = at +% 4;
            },

            .illegal => {
                finish(binding, out_result, .illegal, at, retired_at_entry, null);
                return;
            },

            .unimplemented => |op| {
                finish(binding, out_result, .unimplemented, at, retired_at_entry, op);
                return;
            },
        }
    }
}

/// Try to run a compiled block at the current PC.
///
/// Returns null when there is nothing compiled to run, true when the run is
/// over and `out_result` has been filled in, and false when the caller should
/// keep going from wherever the block left the PC.
fn runCompiledBlock(
    binding: *Binding,
    j: *jit_mod.Jit,
    out_result: *RunResult,
    retired_at_entry: u64,
    return_address: u32,
) ?bool {
    const address = binding.state.pc;
    const block = j.lookup(address) orelse {
        // Not compiled yet. Count the visit; compilation happens once the
        // address has proved it is worth the cost.
        if (j.noteExecution(address)) {
            _ = j.compileAt(memoryFor(binding), address) catch {};
        }
        return null;
    };

    // The block accumulates its own retired count into the guest state before
    // it returns, so nothing has to be added here.
    const outcome = j.run(block, &binding.state, memoryFor(binding));
    if (outcome.faulted) {
        finish(binding, out_result, .memory_fault, outcome.address, retired_at_entry, null);
        return true;
    }
    if (binding.state.pc == return_address) {
        finish(binding, out_result, .returned, binding.state.pc, retired_at_entry, null);
        return true;
    }
    return false;
}

fn finish(
    binding: *Binding,
    out_result: *RunResult,
    status: RunStatus,
    at: u32,
    retired_at_entry: u64,
    op: ?ppc_decode.Op,
) void {
    syncToGuest(binding);
    out_result.* = .{
        .status = @intFromEnum(status),
        .address = at,
        .instructions_retired = binding.state.instructions_retired -% retired_at_entry,
        .unimplemented_opcode = if (op) |o| opcodeName(o) else null,
    };
}

/// A NUL-terminated name for every opcode, built once at compile time so the
/// gap can be reported across the C boundary without allocating on a path that
/// is already failing.
const opcode_names = blk: {
    @setEvalBranchQuota(200_000);
    const fields = @typeInfo(ppc_decode.Op).@"enum".fields;
    var table: [fields.len][:0]const u8 = undefined;
    for (fields) |field| {
        table[field.value] = field.name ++ "";
    }
    break :blk table;
};

fn opcodeName(op: ppc_decode.Op) [*:0]const u8 {
    return opcode_names[@intFromEnum(op)].ptr;
}

// ---------------------------------------------------------------------------
// Tests
//
// The tests drive the ABI the way an embedder does: they build a GuestState
// over a scratch context, bind it, and run. That exercises the sync in both
// directions, which is where a mistake would otherwise only show up as a
// kernel export reading a stale argument.
// ---------------------------------------------------------------------------

const testing = std.testing;

const FakeEmbedder = struct {
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
    cr: u32 = 0,
    memory: [4096]u8 = [_]u8{0} ** 4096,

    // Observations the tests assert on.
    system_calls: u32 = 0,
    resolve_calls: u32 = 0,
    traps: u32 = 0,
    /// Addresses the embedder claims are host functions rather than guest code.
    host_addresses: [4]u32 = [_]u32{0} ** 4,
    /// What the host function writes into r3 when it runs.
    host_result: u64 = 0,

    fn readCr(host: *anyopaque) callconv(.c) u32 {
        return self(host).cr;
    }
    fn writeCr(host: *anyopaque, value: u32) callconv(.c) void {
        self(host).cr = value;
    }
    fn systemCall(host: *anyopaque, lev: u32, addr: u32) callconv(.c) i32 {
        _ = lev;
        _ = addr;
        self(host).system_calls += 1;
        return @intFromEnum(CallStatus.handled);
    }
    fn resolveCall(host: *anyopaque, target: u32, return_address: u32) callconv(.c) i32 {
        _ = return_address;
        const emb = self(host);
        emb.resolve_calls += 1;
        for (emb.host_addresses) |candidate| {
            if (candidate != 0 and candidate == target) {
                // Run the "host function": it writes r3 and returns.
                emb.gpr[3] = emb.host_result;
                return @intFromEnum(CallStatus.handled);
            }
        }
        return @intFromEnum(CallStatus.is_guest_code);
    }
    fn onTrap(host: *anyopaque, addr: u32) callconv(.c) void {
        _ = addr;
        self(host).traps += 1;
    }

    fn self(host: *anyopaque) *FakeEmbedder {
        return @ptrCast(@alignCast(host));
    }

    fn guestState(emb: *FakeEmbedder) GuestState {
        return .{
            .abi_version = abi_version,
            .reserved = 0,
            .gpr = &emb.gpr,
            .fpr = &emb.fpr,
            .vr = &emb.vr,
            .lr = &emb.lr,
            .ctr = &emb.ctr,
            .msr = &emb.msr,
            .fpscr = &emb.fpscr,
            .xer_ca = &emb.xer_ca,
            .xer_ov = &emb.xer_ov,
            .xer_so = &emb.xer_so,
            .vscr_sat = &emb.vscr_sat,
            .vrsave = &emb.vrsave,
            .reserved_val = &emb.reserved_val,
            .virtual_membase = &emb.memory,
            .guest_address_space_size = emb.memory.len,
            .host_context = emb,
            .read_cr = &readCr,
            .write_cr = &writeCr,
            .system_call = &systemCall,
            .resolve_call = &resolveCall,
            .trap = &onTrap,
        };
    }

    fn loadProgram(emb: *FakeEmbedder, at: u32, words: []const u32) void {
        for (words, 0..) |word, i| {
            std.mem.writeInt(u32, emb.memory[at + i * 4 ..][0..4], word, .big);
        }
    }
};

fn resetBindings() void {
    bindings_lock.lock();
    defer bindings_lock.unlock();
    for (&bindings) |*binding| binding.used = false;
}

test "the host reports itself available and identified" {
    try testing.expectEqual(@as(i32, 1), rosette_ppc_host_available());
    try testing.expect(std.mem.len(rosette_ppc_host_identity()) > 0);
}

test "a mismatched ABI version is refused rather than read through" {
    resetBindings();
    var emb = FakeEmbedder{};
    var guest = emb.guestState();
    guest.abi_version = abi_version + 1;
    try testing.expectEqual(@as(i32, 0), rosette_ppc_bind_context(&guest));
}

test "register state syncs in and back out around one request" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.gpr[4] = 10;
    emb.gpr[5] = 32;
    emb.loadProgram(0, &.{
        0x7C642A14, // add r3, r4, r5
        0x4E800020, // blr
    });
    emb.lr = 0x100;

    const guest = emb.guestState();
    try testing.expectEqual(@as(i32, 1), rosette_ppc_bind_context(&guest));

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    // The sum is visible to the embedder, not just inside Rosette.
    try testing.expectEqual(@as(u64, 42), emb.gpr[3]);
    try testing.expectEqual(@as(u64, 2), result.instructions_retired);
    rosette_ppc_release_context(&emb);
}

test "the 4-20-20-20 vertex sub-format executes across the ABI" {
    resetBindings();
    var emb = FakeEmbedder{};
    const four_twenty = ppc_decode.Op.vupkd3d128.info().pattern | (@as(u32, 6) << 18);
    emb.vr[0] = .{ 0, 0, 0xA34567FF, 0xFFF12345 };
    emb.loadProgram(0, &.{
        four_twenty,
        0x44000002, // sc
        0x4E800020, // blr
    });
    emb.lr = 0x100;
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    try testing.expect(result.unimplemented_opcode == null);
    try testing.expectEqual(@as(u32, 1), emb.system_calls);
    try testing.expectEqual([4]u32{ 0x40412345, 0x403FFFFF, 0x40434567, 0x3F80000A }, emb.vr[0]);
    rosette_ppc_release_context(&emb);
}

test "a call into a host function runs it and resumes at LR" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.host_addresses[0] = 0x200;
    emb.host_result = 0xABCD;
    // r0 carries the caller's return address, the way a real guest prologue
    // saves it. Without the mtlr the `blr` would return to the address `bl`
    // just wrote into LR - that is, to itself.
    emb.gpr[0] = 0x100;
    emb.loadProgram(0, &.{
        0x38600000, // li   r3, 0
        0x480001FD, // bl   +0x1FC -> 0x200, which the embedder calls a host
        0x7C0803A6, // mtlr r0
        0x4E800020, // blr
    });
    emb.lr = 0x100;

    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    // The host function's write to r3 survived the resync.
    try testing.expectEqual(@as(u64, 0xABCD), emb.gpr[3]);
    try testing.expect(emb.resolve_calls >= 1);
    rosette_ppc_release_context(&emb);
}

test "an ordinary guest branch is classified once and then cached" {
    resetBindings();
    var emb = FakeEmbedder{};
    // A loop whose back-edge targets the same guest address every iteration.
    emb.loadProgram(0, &.{
        0x38600000, // li   r3, 0
        0x38630001, // addi r3, r3, 1
        0x4200FFFC, // bdnz -4
        0x4E800020, // blr
    });
    emb.ctr = 8;
    emb.lr = 0x100;

    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    try testing.expectEqual(@as(u64, 8), emb.gpr[3]);
    // Eight back-edges, but the target is classified once. Without the cache
    // every loop iteration would cross the ABI boundary twice.
    try testing.expectEqual(@as(u32, 1), emb.resolve_calls);
    rosette_ppc_release_context(&emb);
}

test "invalidating a range drops the cached classification for it" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.loadProgram(0, &.{
        0x38600000, // li   r3, 0
        0x38630001, // addi r3, r3, 1
        0x4200FFFC, // bdnz -4
        0x4E800020, // blr
    });
    emb.ctr = 3;
    emb.lr = 0x100;
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    const before = emb.resolve_calls;

    rosette_ppc_invalidate_range(0, 0x100);
    emb.ctr = 3;
    emb.gpr[3] = 0;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    // The classification had to be asked for again after the invalidation.
    try testing.expect(emb.resolve_calls > before);
    rosette_ppc_release_context(&emb);
}

test "a system call is delivered to the embedder and execution continues" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.loadProgram(0, &.{
        0x44000002, // sc
        0x38600007, // li r3, 7
        0x4E800020, // blr
    });
    emb.lr = 0x100;
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    try testing.expectEqual(@as(u32, 1), emb.system_calls);
    try testing.expectEqual(@as(u64, 7), emb.gpr[3]);
    rosette_ppc_release_context(&emb);
}

test "a guest memory fault is reported with the faulting address" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.loadProgram(0, &.{
        0x3C80FFFF, // lis r4, 0xFFFF   -> far outside the 4KB map
        0x80640000, // lwz r3, 0(r4)
    });
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.memory_fault), result.status);
    try testing.expectEqual(@as(u32, 4), result.address);
    rosette_ppc_release_context(&emb);
}

test "the condition register round-trips through the embedder's accessors" {
    resetBindings();
    var emb = FakeEmbedder{};
    emb.gpr[4] = 5;
    emb.gpr[5] = 5;
    emb.loadProgram(0, &.{
        0x7C042800, // cmpw cr0, r4, r5
        0x4E800020, // blr
    });
    emb.lr = 0x100;
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x100, &result);
    try testing.expectEqual(@intFromEnum(RunStatus.returned), result.status);
    // CR0 = EQ, written back through write_cr rather than left in Rosette.
    try testing.expectEqual(@as(u32, 0b0010) << 28, emb.cr);
    rosette_ppc_release_context(&emb);
}

test "the recompiler is off until an embedder asks for it" {
    resetBindings();
    // A JIT that started itself would change the timing of every run,
    // including the ones being used to diagnose something unrelated.
    try testing.expect(!jit_enabled);
    defer _ = rosette_ppc_set_recompiler_enabled(0);
    if (jit_mod.Jit.available()) {
        try testing.expectEqual(@as(i32, 1), rosette_ppc_set_recompiler_enabled(1));
        try testing.expect(jit_enabled);
    } else {
        try testing.expectEqual(@as(i32, 0), rosette_ppc_set_recompiler_enabled(1));
    }
}

test "a hot loop gives the same answer with and without the recompiler" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;

    // A counted loop whose body is entirely in the compiled subset, run for
    // long enough that the body crosses the hotness threshold and compiles.
    const program = [_]u32{
        0x38600000, // li    r3, 0
        0x38800000, // li    r4, 0
        0x38840001, // addi  r4, r4, 1      <- loop body, address 8
        0x7C632214, // add   r3, r3, r4
        0x2C040064, // cmpwi r4, 100
        0x4082FFF4, // bne   -12
        0x44000002, // sc
    };

    var interpreted: u64 = 0;
    var compiled: u64 = 0;
    for ([_]bool{ false, true }) |use_jit| {
        resetBindings();
        _ = rosette_ppc_set_recompiler_enabled(if (use_jit) 1 else 0);
        defer _ = rosette_ppc_set_recompiler_enabled(0);

        var emb = FakeEmbedder{};
        emb.loadProgram(0, &program);
        const guest = emb.guestState();
        try testing.expectEqual(@as(i32, 1), rosette_ppc_bind_context(&guest));

        var result: RunResult = undefined;
        rosette_ppc_execute(&emb, 0, 0x800, &result);
        // The `sc` at the end is handled by the fake embedder, so the run ends
        // by returning rather than by stopping on the system call.
        try testing.expectEqual(@as(u32, 1), emb.system_calls);
        // 1 + 2 + ... + 100
        try testing.expectEqual(@as(u64, 5050), emb.gpr[3]);
        try testing.expectEqual(@as(u64, 100), emb.gpr[4]);
        if (use_jit) compiled = emb.gpr[3] else interpreted = emb.gpr[3];
        rosette_ppc_release_context(&emb);
    }
    try testing.expectEqual(interpreted, compiled);
}

test "an icbi drops the compiled code for the block it names" {
    if (!jit_mod.Jit.available()) return error.SkipZigTest;
    resetBindings();
    _ = rosette_ppc_set_recompiler_enabled(1);
    defer _ = rosette_ppc_set_recompiler_enabled(0);

    var emb = FakeEmbedder{};
    // A loop that goes hot, then an icbi over its own address range, then the
    // same loop again. The second pass must not run the first pass's code.
    const program = [_]u32{
        0x38800000, // li    r4, 0
        0x38840001, // addi  r4, r4, 1
        0x2C040014, // cmpwi r4, 20
        0x4082FFF8, // bne   -8
        0x38A00000, // li    r5, 0
        0x7CA5FFAC, // icbi  r5, r31
        0x44000002, // sc
    };
    emb.loadProgram(0, &program);
    emb.gpr[31] = 0;
    const guest = emb.guestState();
    _ = rosette_ppc_bind_context(&guest);

    var result: RunResult = undefined;
    rosette_ppc_execute(&emb, 0, 0x800, &result);
    try testing.expectEqual(@as(u64, 20), emb.gpr[4]);

    // The icbi ran, so nothing compiled for the block it covered survives.
    bindings_lock.lock();
    const binding = findBinding(&emb).?;
    const has_block = if (binding.jit) |*j| j.lookup(4) != null else false;
    bindings_lock.unlock();
    try testing.expect(!has_block);
    rosette_ppc_release_context(&emb);
}

test "binding refuses a context once the table is full" {
    resetBindings();
    // Heap-allocated: 64 embedders carry 64 guest address spaces between them,
    // which is far more than a test stack should hold.
    const embedders = try testing.allocator.alloc(FakeEmbedder, max_bindings);
    defer testing.allocator.free(embedders);
    for (embedders) |*emb| {
        emb.* = FakeEmbedder{};
        const guest = emb.guestState();
        try testing.expectEqual(@as(i32, 1), rosette_ppc_bind_context(&guest));
    }
    var overflow = FakeEmbedder{};
    const guest = overflow.guestState();
    // Refusing beats quietly handing a 65th thread another thread's registers.
    try testing.expectEqual(@as(i32, 0), rosette_ppc_bind_context(&guest));
    resetBindings();
}
