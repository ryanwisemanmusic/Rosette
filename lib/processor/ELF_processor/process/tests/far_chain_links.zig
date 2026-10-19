//! Real executable transfers across a 144 MiB code-cache gap, plus a
//! shuffled, data-bearing production-translator benchmark. No GPU work.
const P = @import("../../process.zig");
const I = P.__ProcessInternals;
const std = I._std;
const t = std.testing;
const core = I._block_jit;
const links = core.direct_links;
const far = links.far_links;
const base = I._MEM_BASE;
const f = @import("direct_links.zig");
const glue = @import("../impl/block_jit.zig");
const guest_memory = @import("../impl/guest_memory.zig");
const gap = 144 << 20;

fn precompile(state: *P.ElfState, jit: anytype, rip: u64) !*core.Block {
    const block = state.compileBlockJit(jit, rip) orelse return error.CompileFailed;
    errdefer I._freeTranslatedBlock(state.allocator, block);
    while (true) {
        const start = jit.firstSlot(rip);
        for (start..start + I._BLOCK_JIT_WAYS) |slot| {
            if (jit.blocks[slot] == null) {
                jit.blocks[slot] = block;
                return block;
            }
        }
        jit.pressure = std.math.maxInt(u64);
        if (!jit.growIfPressed(state.allocator)) return error.NoTableSpace;
    }
}

fn preparePair(enabled: bool) !f.Fixture {
    far.enabled = enabled;
    const fixture = try f.Fixture.init();
    errdefer fixture.deinit();
    const jit = fixture.state.blockJitActive().?;
    _ = try precompile(fixture.state, jit, f.a_rip);
    jit.memory.used += gap; // Virtual spacing only; no padding is touched/executed.
    _ = try precompile(fixture.state, jit, f.b_rip);
    return fixture;
}

test "far links actual positive and negative displacements preserve state and budgets" {
    defer far.enabled = true;
    const old = try preparePair(false);
    defer old.deinit();
    const new = try preparePair(true);
    defer new.deinit();
    try f.runPasses(old.state, 100_000);
    try f.runPasses(new.state, 100_000);
    try t.expectEqualDeep(old.state.regs, new.state.regs);
    try t.expectEqual(@as(u64, 100_000), new.state.regs.rax);
    const a = new.block(f.a_rip);
    const b = new.block(f.b_rip);
    try t.expect(@intFromPtr(b.code.ptr) - @intFromPtr(a.code.ptr) > 128 << 20);
    try t.expect(links.linked(a, f.b_rip, b, &new.state.block_jit.?.memory));
    try t.expect(links.linked(b, f.a_rip, a, &new.state.block_jit.?.memory));
    try t.expect(!links.linked(old.block(f.a_rip), f.b_rip, old.block(f.b_rip), &old.state.block_jit.?.memory));
    const jit = new.state.block_jit.?;
    try t.expect(jit.direct_veneers >= 2);
    try t.expect(jit.chain_exits_budget > 10);
    try t.expectEqual(old.state.block_jit.?.instructions_retired, jit.instructions_retired);
    const again = links.link(a, f.b_rip, b, &new.state.block_jit.?.memory);
    try t.expectEqual(@as(u32, 0), again.patched);
}

test "far links reject dropped recycled rewritten and cross-thread disarmed successors" {
    defer far.enabled = true;
    for (0..3) |scenario| {
        const p = try preparePair(true);
        defer p.deinit();
        try f.runPasses(p.state, 32);
        const jit = p.state.block_jit.?;
        const b = p.block(f.b_rip);
        try t.expect(links.linked(p.block(f.a_rip), f.b_rip, b, &p.state.block_jit.?.memory));
        if (scenario == 0) {
            const slot = p.state.blockJitFindValidSlot(jit, f.b_rip).?.slot;
            glue.dropBlockJitSlot(p.state, jit, slot);
            const other = p.state.compileBlockJit(jit, f.c_rip).?;
            try t.expectEqual(@intFromPtr(b), @intFromPtr(other));
            p.state.regs.rcx = 0;
            try f.runPasses(p.state, 32);
            try t.expectEqual(@as(u64, 0), p.state.regs.rcx);
            I._freeTranslatedBlock(p.state.allocator, other);
        } else if (scenario == 1) {
            p.state.mem[@intCast(f.b_rip - base + 2)] = 2;
            guest_memory.bumpWindowsImageCodeGeneration(p.state, f.b_rip, 3);
            try f.runPasses(p.state, 32);
        } else {
            const worker = try std.Thread.spawn(.{}, struct {
                fn run(block: *core.Block) void {
                    block.disarmChain();
                }
            }.run, .{b});
            worker.join();
            const before = jit.dispatch_relinks;
            try f.runPasses(p.state, 32);
            try t.expect(jit.dispatch_relinks >= before + 32);
        }
        try t.expectEqual(@as(u64, 64), p.state.regs.rax);
        try t.expectEqual(@as(u64, if (scenario == 1) 96 else 64), p.state.regs.rbx);
    }
}

test "far links exhausted local pools keep the original executable route" {
    defer far.enabled = true;
    const p = try preparePair(true);
    defer p.deinit();
    const jit = p.state.block_jit.?;
    for ([_]u64{ f.a_rip, f.b_rip }) |rip| {
        const block = p.block(rip);
        while (jit.memory.branch_islands.take(jit.memory.memory, @intFromPtr(block.code.ptr)) != null) {}
    }
    try f.runPasses(p.state, 128);
    try t.expectEqual(@as(u64, 128), p.state.regs.rax);
    try t.expectEqual(@as(u64, 128), p.state.regs.rbx);
    try t.expectEqual(@as(u64, 0), jit.direct_veneers);
    try t.expect(!links.linked(p.block(f.a_rip), f.b_rip, p.block(f.b_rip), &jit.memory));
}

test "far links ADRP round trip covers page offsets signed limits and out-of-reach fallback" {
    const memory = [_]u32{0} ** 8;
    const at = @intFromPtr(&memory) + 8;
    const page = at & ~@as(u64, 4095);
    for ([_]i64{ -(1 << 32), -(144 << 20), -4096, 0, 4095, 144 << 20, (1 << 32) - 4096 }) |distance| {
        const target = @as(u64, @intCast(@as(i64, @intCast(page)) + distance));
        const words = far.instructions(at, target).?;
        const instruction = words[0];
        const signed: i21 = @bitCast(@as(u21, @truncate(((instruction >> 29) & 3) | (((instruction >> 5) & 0x7FFFF) << 2))));
        const result = @as(i64, @intCast(page)) + @as(i64, signed) * 4096 + ((words[1] >> 10) & 4095);
        try t.expectEqual(target, @as(u64, @intCast(result)));
    }
    try t.expect(far.instructions(at, page + (1 << 32)) == null);
    try t.expect(far.instructions(at, page - (1 << 32) - 4096) == null);
}

const code: usize = 0x100000;
const stride = 128;
const context: usize = 0x80000;
const guest: usize = 0x30000;
const body = [_]u8{
    0x8B, 0x46, 0x40, 0x03, 0x46, 0x44, 0x89, 0x46, 0x48,
    0x8B, 0x4E, 0x4C, 0x0F, 0x38, 0xF0, 0x14, 0x0F, 0x01,
    0xC2, 0x0F, 0x38, 0xF1, 0x14, 0x0F, 0x89, 0x56, 0x50,
};
fn rel32(from: usize, to: usize) [4]u8 {
    return @bitCast(@as(i32, @intCast(@as(i64, @intCast(to)) - @as(i64, @intCast(from)))));
}
fn cpu() u64 {
    var stamp: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &stamp) == 0);
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}
const Measurement = struct { ns: u64, retired: u64, blocks: u64, entries: u64, misses: u64, checksum: u64 };
const SavedSite = struct { from: *core.Block, site: links.Site, original: u32, veneer_branch: ?u32 = null };
const Program = struct {
    state: *P.ElfState,
    start: u64,
    exit: u64,
    count: usize,
    slots: usize,
    total_passes: u64 = 0,
    bytes: u64,
    saved_sites: []SavedSite,
    fn init(count: usize, slots: usize, separated: bool, enabled: bool) !@This() {
        far.enabled = enabled;
        const state = try t.allocator.create(P.ElfState);
        state.* = P.ElfState.init(t.allocator);
        errdefer {
            state.deinit();
            t.allocator.destroy(state);
        }
        state.setParallelGuestExecution(true);
        state.windows_runtime_enabled = true;
        state.image_low = base + code;
        state.image_high = base + code + count * stride;
        state.configureWindowsExecutableRanges(&.{.{ .guest_base = state.image_low, .length = count * stride }});
        state.block_jit_enabled = true;
        state.block_jit_hot_threshold = 1;
        state.regs.r12 = base + context;
        state.regs.rdi = base + guest;
        state.regs.rsp = base + 0x7f000;
        state.regs.rflags = 2;
        for (0..slots) |i| {
            std.mem.writeInt(u32, state.mem[context + i * 128 + 0x40 ..][0..4], 3, .little);
            std.mem.writeInt(u32, state.mem[context + i * 128 + 0x44 ..][0..4], 4, .little);
            std.mem.writeInt(u32, state.mem[context + i * 128 + 0x4c ..][0..4], @intCast(i * 8), .little);
        }
        const order = try t.allocator.alloc(usize, count);
        defer t.allocator.free(order);
        for (order, 0..) |*i, n| i.* = n;
        var random = std.Random.DefaultPrng.init(0xFAA_2026 + count);
        random.random().shuffle(usize, order);
        var exit: usize = 0;
        for (order, 0..) |index, position| {
            var at = code + index * stride;
            state.mem[at..][0..4].* = .{ 0x49, 0x8D, 0xB4, 0x24 }; // lea rsi,[r12+slot*128]
            std.mem.writeInt(u32, state.mem[at + 4 ..][0..4], @intCast((index % slots) * 128), .little);
            at += 8;
            for (0..3) |_| {
                @memcpy(state.mem[at..][0..body.len], &body);
                at += body.len;
            }
            if (position + 1 < count) {
                state.mem[at] = 0xE9;
                state.mem[at + 1 ..][0..4].* = rel32(at + 5, code + order[position + 1] * stride);
            } else {
                state.mem[at..][0..5].* = .{ 0x49, 0xFF, 0xC8, 0x0F, 0x85 }; // dec r8; jnz first
                state.mem[at + 5 ..][0..4].* = rel32(at + 9, code + order[0] * stride);
                state.mem[at + 9 ..][0..5].* = .{ 0x48, 0x39, 0xE4, 0xEB, 0xFE };
                exit = at + 12;
            }
        }
        const jit = state.blockJitActive().?;
        var bytes: u64 = 0;
        var saved_sites: std.ArrayList(SavedSite) = .empty;
        errdefer saved_sites.deinit(t.allocator);
        for (0..count) |index| {
            if (separated and index == count / 2) jit.memory.used += gap;
            const block = try precompile(state, jit, base + code + index * stride);
            bytes += block.code.len * 4;
            for (block.links.sites()) |site| {
                const word: *const u32 = @ptrFromInt(@intFromPtr(block.code.ptr) + site.offset);
                try saved_sites.append(t.allocator, .{ .from = block, .site = site, .original = word.* });
            }
        }
        var p: @This() = .{ .state = state, .start = base + code + order[0] * stride, .exit = base + exit, .count = count, .slots = slots, .bytes = bytes, .saved_sites = try saved_sites.toOwnedSlice(t.allocator) };
        _ = try p.run(3); // Prepare all links and TLBs before any paired timing.
        return p;
    }
    fn deinit(p: *@This()) void {
        p.state.setParallelGuestExecution(false);
        p.state.deinit();
        t.allocator.destroy(p.state);
        t.allocator.free(p.saved_sites);
    }
    fn setLinks(p: *@This(), variant: u2) void {
        const jit = p.state.block_jit.?;
        std.debug.assert(jit.lifetime.active_executions == 0);
        // Restore only out-of-range sites; near branches remain patched.
        // Every timed variant uses the very same addresses and instructions
        // apart from these sites and their reserved veneers.
        for (p.saved_sites) |*saved| {
            const slot: *u32 = @ptrFromInt(@intFromPtr(saved.from.code.ptr) + saved.site.offset);
            if (far.current(&jit.memory, @intFromPtr(slot)) != null) {
                saved.veneer_branch = slot.*;
                jit.memory.beginWrite();
                @atomicStore(u32, slot, saved.original, .release);
                jit.memory.endWrite(slot[0..1]);
            }
        }
        far.link_enabled = variant == 2;
        if (variant == 0) return;
        for (p.saved_sites) |saved| {
            const to = p.state.blockJitFindValidSlot(jit, saved.site.rip) orelse continue;
            // Restore this fixture's previously allocated pool slot rather
            // than consuming another slot on every A/B switch.
            if (saved.veneer_branch) |word| {
                const slot: *u32 = @ptrFromInt(@intFromPtr(saved.from.code.ptr) + saved.site.offset);
                jit.memory.beginWrite();
                @atomicStore(u32, slot, word, .release);
                jit.memory.endWrite(slot[0..1]);
            }
            if (variant == 2) {
                _ = links.link(saved.from, saved.site.rip, to.block, &jit.memory);
            } else {
                const target = @intFromPtr(to.block.code.ptr) + to.block.links.entry;
                const at = @intFromPtr(saved.from.code.ptr) + saved.site.offset;
                const distance = @as(i64, @intCast(target)) - @as(i64, @intCast(at));
                if (distance >= -(128 << 20) and distance < 128 << 20) continue;
                const patch = far.plan(&jit.memory, at, target) orelse continue;
                const words = [_]u32{ 0x58000050, @import("arm64_encode").br(16), @truncate(target), @truncate(target >> 32) };
                jit.memory.beginWrite();
                for (patch.code, words) |*word, value| word.* = value;
                @as(*u32, @ptrFromInt(at)).* = patch.word;
                jit.memory.endWrite(patch.code);
                jit.memory.endWrite(@as([*]u32, @ptrFromInt(at))[0..1]);
            }
        }
    }
    fn resetData(p: *@This()) void {
        for (0..p.slots) |i| @memset(p.state.mem[guest + i * 8 ..][0..8], 0);
        p.total_passes = 0;
    }
    fn run(p: *@This(), passes: u64) !Measurement {
        const jit = p.state.block_jit.?;
        const retired = jit.instructions_retired;
        const blocks = jit.executions;
        const entries = jit.dispatch_entries;
        const misses = jit.chain_exits_miss;
        p.state.regs.rip = p.start;
        p.state.regs.r8 = passes;
        const start = cpu();
        var steps: usize = 0;
        while (p.state.regs.rip != p.exit and !p.state.terminated) : (steps += 1) {
            _ = p.state.step();
            if (steps > 10_000_000) return error.Stalled;
        }
        const elapsed = cpu() - start;
        p.total_passes += passes;
        var checksum: u64 = 0;
        for (0..p.slots) |i| {
            const actual = std.mem.readInt(u32, p.state.mem[guest + i * 8 ..][0..4], .big);
            const expected: u32 = @truncate(p.total_passes * (p.count / p.slots) * 21);
            try t.expectEqual(expected, actual);
            checksum += actual;
        }
        return .{ .ns = elapsed, .retired = jit.instructions_retired - retired, .blocks = jit.executions - blocks, .entries = jit.dispatch_entries - entries, .misses = jit.chain_exits_miss - misses, .checksum = checksum };
    }
};

test "far links shuffled production loops retain retirement and data across placement and data sizes" {
    defer far.enabled = true;
    for ([_]bool{ false, true }) |separated| {
        var a = try Program.init(64, 16, separated, false);
        defer a.deinit();
        var b = try Program.init(64, 16, separated, true);
        defer b.deinit();
        const old = try a.run(4);
        const new = try b.run(4);
        try t.expectEqual(old.retired, new.retired);
        try t.expectEqual(old.checksum, new.checksum);
        try t.expectEqual(a.bytes, b.bytes);
        try t.expectEqualDeep(a.state.regs, b.state.regs);
        if (separated) try t.expect(b.state.block_jit.?.direct_veneers != 0);
    }
}

test "far links same executable reverts to shared dispatch and relinks each veneer design exactly" {
    defer far.enabled = true;
    defer far.link_enabled = true;
    var p = try Program.init(64, 16, true, true);
    defer p.deinit();
    var reference: ?@TypeOf(p.state.regs) = null;
    for ([_]u2{ 0, 1, 2, 0, 2 }) |variant| {
        p.setLinks(variant);
        p.resetData();
        p.state.regs.r10 = 0xC0FFEE1234;
        p.state.regs.r13 = 0xABCD5678;
        _ = try p.run(5);
        if (reference) |expected| try t.expectEqualDeep(expected, p.state.regs) else reference = p.state.regs;
    }
}

test "far links paired production CPU benchmark" {
    if (std.c.getenv("ROSETTE_FAR_LINK_BENCH") == null) return error.SkipZigTest;
    defer far.enabled = true;
    defer far.link_enabled = true;
    for (0..8) |profile| {
        const count: usize = if (profile % 4 < 2) 512 else 4096;
        const slots: usize = if (profile % 2 == 0) 16 else @min(4096, count);
        const separated = profile >= 4;
        var p = try Program.init(count, slots, separated, true);
        defer p.deinit();
        for (0..7) |pair| {
            var results: [3]Measurement = undefined;
            for (if (pair % 2 == 0) [_]u2{ 0, 1, 2 } else [_]u2{ 2, 1, 0 }) |variant| {
                p.setLinks(variant);
                p.resetData();
                _ = try p.run(1);
                const compiled = p.state.block_jit.?.compiled;
                const m = try p.run(@intCast(1_000_000 / count));
                try t.expectEqual(compiled, p.state.block_jit.?.compiled);
                results[variant] = m;
                std.debug.print("far_links profile={d} pair={d} variant={d} count={d} data_slots={d} separated={} cpu_ns={d} retired={d} blocks={d} entries={d} misses={d} checksum={d} code_bytes={d} veneers={d}\n", .{ profile, pair, variant, count, slots, separated, m.ns, m.retired, m.blocks, m.entries, m.misses, m.checksum, p.bytes, p.state.block_jit.?.direct_veneers });
            }
            for (1..3) |i| {
                try t.expectEqual(results[0].retired, results[i].retired);
                try t.expectEqual(results[0].blocks, results[i].blocks);
                try t.expectEqual(results[0].checksum, results[i].checksum);
            }
        }
    }
}
