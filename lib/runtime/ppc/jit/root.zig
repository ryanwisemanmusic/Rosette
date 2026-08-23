//! The PowerPC block recompiler: cache, hotness policy, and dispatch.
//!
//! Compiling is not free, and most guest addresses are executed once. The
//! policy here is the standard one and the reason it is standard: count
//! executions per address, compile at a threshold, and interpret everything
//! below it. A JIT that compiles on first sight spends more time compiling
//! cold code than the interpreter would have spent running it.
//!
//! Invalidation is the part that has to be right rather than fast. Guest code
//! that is decrypted, patched, or unloaded reuses addresses, and a stale block
//! would execute the *previous* contents of those addresses - a failure that
//! looks like miscompilation and moves when anything about the load order
//! changes. `invalidate` drops every block that overlaps the range, and a
//! module load that cannot be bounded drops everything.

const std = @import("std");
const ppc_decode = @import("ppc_decode");
const state_mod = @import("../state.zig");
const memory_mod = @import("../memory.zig");

pub const code_cache = @import("code_cache.zig");
pub const assembler = @import("assembler.zig");
pub const compile_mod = @import("compile.zig");

pub const CodeCache = code_cache.CodeCache;
pub const Assembler = assembler.Assembler;
pub const Block = compile_mod.Block;
pub const BlockExit = compile_mod.BlockExit;
pub const BlockFn = compile_mod.BlockFn;
pub const ExitReason = compile_mod.ExitReason;
pub const isCompilable = compile_mod.isCompilable;

const State = state_mod.State;
const Memory = memory_mod.Memory;

pub const Error = error{OutOfMemory} || code_cache.Error;

/// How many times an address must be executed before it is worth compiling.
pub const default_hot_threshold: u32 = 8;

/// The most guest instructions one block may cover. A bound keeps a single
/// compilation from monopolising the code cache and keeps invalidation ranges
/// small enough to be precise.
pub const default_max_block: u32 = 64;

/// What running a compiled block did.
pub const RunResult = struct {
    /// Guest instructions the block retired.
    retired: u32,
    /// Where the guest resumes.
    address: u32,
    /// Whether it stopped on a memory fault rather than running to its end.
    faulted: bool,
};

pub const Stats = struct {
    blocks_compiled: u64 = 0,
    blocks_executed: u64 = 0,
    instructions_compiled: u64 = 0,
    instructions_executed: u64 = 0,
    compile_refusals: u64 = 0,
    invalidations: u64 = 0,
};

pub const Jit = struct {
    allocator: std.mem.Allocator,
    cache: CodeCache,
    blocks: std.AutoHashMapUnmanaged(u32, Block) = .empty,
    hotness: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    hot_threshold: u32 = default_hot_threshold,
    max_block: u32 = default_max_block,
    stats: Stats = .{},
    /// Scratch the compiled code writes its exit record into. One per JIT
    /// because a JIT belongs to one guest thread.
    exit: BlockExit = .{},

    pub fn init(allocator: std.mem.Allocator, capacity_bytes: usize) Error!Jit {
        return .{
            .allocator = allocator,
            .cache = try CodeCache.init(capacity_bytes),
        };
    }

    pub fn deinit(self: *Jit) void {
        self.blocks.deinit(self.allocator);
        self.hotness.deinit(self.allocator);
        self.cache.deinit();
    }

    pub fn available() bool {
        return CodeCache.available();
    }

    pub fn lookup(self: *const Jit, address: u32) ?Block {
        return self.blocks.get(address);
    }

    /// Count one execution of `address` and report whether it has become hot.
    ///
    /// The counter saturates at the threshold rather than continuing to climb:
    /// an address that has already been compiled does not need a running total,
    /// and one that failed to compile should not be retried on every pass.
    pub fn noteExecution(self: *Jit, address: u32) bool {
        const entry = self.hotness.getOrPut(self.allocator, address) catch return false;
        if (!entry.found_existing) entry.value_ptr.* = 0;
        if (entry.value_ptr.* >= self.hot_threshold) return false;
        entry.value_ptr.* += 1;
        return entry.value_ptr.* == self.hot_threshold;
    }

    /// Compile the block starting at `address`, or return null when nothing at
    /// that address is compilable.
    pub fn compileAt(self: *Jit, memory: Memory, address: u32) Error!?Block {
        // The compiler addresses guest memory as `membase[guest_address]`. A
        // window that starts somewhere else would need every effective address
        // biased, so it is refused rather than compiled against the wrong base.
        if (memory.origin != 0) {
            self.stats.compile_refusals += 1;
            return null;
        }

        var count: u32 = 0;
        const code = compile_mod.compile(
            self.allocator,
            memory,
            address,
            self.max_block,
            &count,
        ) catch |err| switch (err) {
            error.OutOfMemory => return Error.OutOfMemory,
            else => {
                self.stats.compile_refusals += 1;
                return null;
            },
        };
        defer self.allocator.free(code);

        const slot = self.cache.reserve(code.len) catch |err| switch (err) {
            code_cache.Error.OutOfCodeSpace => {
                // The cache is full. Dropping everything is the only safe
                // reclamation without a quiescence protocol, and the blocks
                // that mattered will be recompiled by their own hotness.
                self.reset();
                self.stats.compile_refusals += 1;
                return null;
            },
            else => return err,
        };

        self.cache.beginWrite();
        @memcpy(slot, code);
        self.cache.endWrite(slot);

        const block = Block{
            .guest_start = address,
            .guest_end = address +% (count * 4),
            .instruction_count = count,
            .code = slot,
        };
        try self.blocks.put(self.allocator, address, block);
        self.stats.blocks_compiled += 1;
        self.stats.instructions_compiled += count;
        return block;
    }

    /// Run a compiled block against `state` and `memory`.
    pub fn run(self: *Jit, block: Block, state: *State, memory: Memory) RunResult {
        self.exit = .{};
        block.entry()(state, memory.base, memory.len, &self.exit);
        self.stats.blocks_executed += 1;
        self.stats.instructions_executed += self.exit.retired;
        return .{
            .retired = self.exit.retired,
            .address = self.exit.address,
            .faulted = self.exit.reason == @intFromEnum(ExitReason.memory_fault),
        };
    }

    /// Drop every block whose guest range overlaps [low, high).
    pub fn invalidate(self: *Jit, low: u32, high: u32) void {
        if (high <= low) return;
        self.stats.invalidations += 1;

        var stale: std.ArrayList(u32) = .empty;
        defer stale.deinit(self.allocator);
        var it = self.blocks.iterator();
        while (it.next()) |entry| {
            const block = entry.value_ptr.*;
            if (block.guest_start < high and block.guest_end > low) {
                stale.append(self.allocator, entry.key_ptr.*) catch {
                    // Losing track of a stale block would let it run against
                    // rewritten guest code. If the list cannot be built, drop
                    // everything instead - correct, and rare.
                    self.reset();
                    return;
                };
            }
        }
        for (stale.items) |address| {
            _ = self.blocks.remove(address);
            _ = self.hotness.remove(address);
        }
    }

    /// Drop every block and reclaim the code cache.
    pub fn reset(self: *Jit) void {
        self.blocks.clearRetainingCapacity();
        self.hotness.clearRetainingCapacity();
        self.cache.reset();
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = code_cache;
    _ = assembler;
    _ = compile_mod;
}
