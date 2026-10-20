//! Xenia's per-draw Vulkan call stream, replayed end to end on the CPU.
//!
//! A translated guest loop plays the part of Xenia's
//! `DeferredCommandBuffer::Execute`: it reads one command record, loads the
//! Microsoft x64 argument registers and stack slots, and calls the
//! `vulkan-1.dll` thunk `vkGetDeviceProcAddr` handed out. Every call then
//! takes the production route - the PE step boundary, the import stub, the
//! runtime lock, the Windows/SysV adapter, the dyld forwarder's marshalling
//! and provenance, and the hybrid command FIFO - into a stub driver that
//! counts and checksums every native call it receives.
//!
//! The command mix per eight draws follows the supplied 2026-10-16 Custom
//! Games run's own counters (descriptor binds 1.77 per draw, descriptor
//! updates 0.86, pipeline binds 0.47, barriers 0.25, push constants 0.19):
//! the calls that make up about 90% of its 23.5 million Vulkan calls.
//! No GPU work, Vulkan driver or Xenia code runs; the timings are CPU time on
//! the calling thread and are not frame-rate measurements.

const std = @import("std");
const P = @import("elf_processor_state");
const State = P.ElfState;
const I = P.__ProcessInternals;
const forwarder_module = @import("windows_guest_forwarder");
const Bridge = forwarder_module.Bridge;
const abi = @import("gpu").vulkan.abi;
const t = std.testing;

const base = I._MEM_BASE;
const code = base + 0x1000;
const stack_top = base + 0x80000;
const stream_base = base + 0x100000;
const data_base = base + 0x400000;
const record_bytes = 96;

const command_buffer: u64 = 0x111;
const native_command_buffer: u64 = 0x2220;
const device: u64 = 0x100;
const set_count = 2048;
const pipeline_count = 64;
const layout_count = 4;
const buffer_count = 64;
const view_count = 256;
const sampler_count = 32;
const compute_count = 16;
const tracked_filler = 2564;
const tracked_spacing = tracked_filler / pipeline_count;

/// The replay loop, assembled from Intel syntax with llvm-mc:
/// load stub, rcx, rdx, r8, r9 and six stack slots from [rsi], `call rax`,
/// advance rsi by one record and wrap at rdi to r12, `dec rbx; jnz`.
const program = [_]u8{
    0x48, 0x8b, 0x06, 0x48, 0x8b, 0x4e, 0x08, 0x48, 0x8b, 0x56, 0x10, 0x4c, 0x8b, 0x46, 0x18, 0x4c,
    0x8b, 0x4e, 0x20, 0x4c, 0x8b, 0x56, 0x28, 0x4c, 0x89, 0x54, 0x24, 0x20, 0x4c, 0x8b, 0x56, 0x30,
    0x4c, 0x89, 0x54, 0x24, 0x28, 0x4c, 0x8b, 0x56, 0x38, 0x4c, 0x89, 0x54, 0x24, 0x30, 0x4c, 0x8b,
    0x56, 0x40, 0x4c, 0x89, 0x54, 0x24, 0x38, 0x4c, 0x8b, 0x56, 0x48, 0x4c, 0x89, 0x54, 0x24, 0x40,
    0x4c, 0x8b, 0x56, 0x50, 0x4c, 0x89, 0x54, 0x24, 0x48, 0xff, 0xd0, 0x48, 0x83, 0xc6, 0x60, 0x48,
    0x39, 0xfe, 0x72, 0x03, 0x4c, 0x89, 0xe6, 0x48, 0xff, 0xcb, 0x75, 0xa4, 0xeb, 0xfe,
};
const done_rip = code + program.len - 2;

pub const Kind = enum(u8) {
    set_viewport,
    set_scissor,
    bind_pipeline,
    update_descriptor_sets,
    bind_descriptor_sets,
    push_constants,
    pipeline_barrier,
    bind_index_buffer,
    draw_indexed,

    fn name(kind: Kind) []const u8 {
        return switch (kind) {
            .set_viewport => "vkCmdSetViewport",
            .set_scissor => "vkCmdSetScissor",
            .bind_pipeline => "vkCmdBindPipeline",
            .update_descriptor_sets => "vkUpdateDescriptorSets",
            .bind_descriptor_sets => "vkCmdBindDescriptorSets",
            .push_constants => "vkCmdPushConstants",
            .pipeline_barrier => "vkCmdPipelineBarrier",
            .bind_index_buffer => "vkCmdBindIndexBuffer",
            .draw_indexed => "vkCmdDrawIndexed",
        };
    }
};
const kind_count = @typeInfo(Kind).@"enum".fields.len;

/// Counts and a checksum of every argument the stub driver received. The
/// FIFO worker writes them for queued commands and the calling thread for
/// synchronous ones; a drain orders the two before any comparison.
pub const Driver = struct {
    var calls: [kind_count]u64 = @splat(0);
    var checksum: u64 = 0;
    var descriptors: u64 = 0;
    var errors: u64 = 0;

    fn reset() void {
        calls = @splat(0);
        checksum = 0;
        descriptors = 0;
        errors = 0;
    }
    fn note(kind: Kind, value: u64) void {
        calls[@intFromEnum(kind)] += 1;
        checksum = (checksum ^ value) *% 0x100000001b3;
    }
    fn buffer(cb: abi.CommandBuffer) void {
        if (@intFromPtr(cb) != native_command_buffer) errors += 1;
    }
    fn viewport(cb: abi.CommandBuffer, first: u32, count: u32, values: [*]const abi.Viewport) callconv(.c) void {
        buffer(cb);
        if (first != 0 or count != 1 or values[0].width != 1280) errors += 1;
        note(.set_viewport, count);
    }
    fn scissor(cb: abi.CommandBuffer, first: u32, count: u32, values: [*]const abi.Rect2D) callconv(.c) void {
        buffer(cb);
        if (first != 0 or count != 1 or values[0].extent.width != 1280) errors += 1;
        note(.set_scissor, count);
    }
    fn pipeline(cb: abi.CommandBuffer, point: u32, value: u64) callconv(.c) void {
        buffer(cb);
        if (point > 1) errors += 1;
        note(.bind_pipeline, value +% point);
    }
    fn update(dev: abi.Device, write_count: u32, writes: ?[*]const abi.WriteDescriptorSet, copy_count: u32, _: ?[*]const abi.CopyDescriptorSet) callconv(.c) void {
        if (@intFromPtr(dev) != device or write_count != 3 or copy_count != 0) errors += 1;
        var value: u64 = 0;
        for (writes.?[0..write_count]) |write| {
            value +%= write.dst_set +% write.descriptor_count;
            descriptors += write.descriptor_count;
            if (write.image_info) |infos| for (infos[0..write.descriptor_count]) |info| {
                value +%= info.image_view +% info.sampler;
            };
            if (write.buffer_info) |infos| for (infos[0..write.descriptor_count]) |info| {
                value +%= info.buffer +% info.range;
            };
        }
        note(.update_descriptor_sets, value);
    }
    fn sets(cb: abi.CommandBuffer, point: u32, layout: u64, first: u32, count: u32, values: [*]const u64, dynamic_count: u32, _: ?[*]const u32) callconv(.c) void {
        buffer(cb);
        if (point != 0 or first != 0 or count != 2 or dynamic_count != 0) errors += 1;
        note(.bind_descriptor_sets, layout +% values[0] +% values[1]);
    }
    fn push(cb: abi.CommandBuffer, layout: u64, stages: u32, offset: u32, size: u32, data: ?*const anyopaque) callconv(.c) void {
        buffer(cb);
        if (stages != 0x10 or offset != 0 or size != 16) errors += 1;
        const bytes: [*]const u8 = @ptrCast(data.?);
        note(.push_constants, layout +% std.mem.readInt(u32, bytes[0..4], .little));
    }
    fn barrier(cb: abi.CommandBuffer, src: u32, dst: u32, flags: u32, memory_count: u32, _: ?*const anyopaque, buffer_count_: u32, buffers: ?*const anyopaque, image_count: u32, _: ?[*]const abi.ImageMemoryBarrier) callconv(.c) void {
        buffer(cb);
        if (src != 0x1000 or dst != 0x8 or flags != 0 or memory_count != 0 or buffer_count_ != 1 or image_count != 0) errors += 1;
        const values: [*]const abi.BufferMemoryBarrier = @ptrCast(@alignCast(buffers.?));
        note(.pipeline_barrier, values[0].buffer +% values[0].size);
    }
    fn index(cb: abi.CommandBuffer, value: abi.Buffer, offset: u64, index_type: u32) callconv(.c) void {
        buffer(cb);
        if (index_type != 0) errors += 1;
        note(.bind_index_buffer, value +% offset);
    }
    fn draw(cb: abi.CommandBuffer, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) callconv(.c) void {
        buffer(cb);
        if (instance_count != 1 or vertex_offset != 0 or first_instance != 0) errors += 1;
        note(.draw_indexed, @as(u64, index_count) << 32 | first_index);
    }
};

fn cpu() u64 {
    var value: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &value) == 0);
    return @as(u64, @intCast(value.sec)) * std.time.ns_per_s + @as(u64, @intCast(value.nsec));
}

/// Every thread of the test process, including the FIFO worker, so a
/// polling handoff cannot hide its own CPU on the other core.
fn processCpu() u64 {
    var value: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.PROCESS_CPUTIME_ID, &value) == 0);
    return @as(u64, @intCast(value.sec)) * std.time.ns_per_s + @as(u64, @intCast(value.nsec));
}

fn wall() u64 {
    var value: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.UPTIME_RAW, &value) == 0);
    return @as(u64, @intCast(value.sec)) * std.time.ns_per_s + @as(u64, @intCast(value.nsec));
}

/// Cache pressure for the `cold` profile: Xenia's own work between two
/// Vulkan calls evicts most of what the previous call touched. Every
/// `scrub_period` calls the hook reads one byte per cache line of a 1 MiB
/// buffer before dispatching; both variants pay exactly the same scrub.
const scrub_bytes = 1 << 20;
const scrub_period = 4;
var scrub_buffer: [scrub_bytes]u8 align(128) = undefined;
var scrub_enabled = false;
var scrub_calls: u64 = 0;
var scrub_sink: u64 = 0;

fn scrub() void {
    scrub_calls +%= 1;
    if (scrub_calls % scrub_period != 0) return;
    var sum: u64 = 0;
    var offset: usize = 0;
    while (offset < scrub_bytes) : (offset += 64) sum +%= @as(*volatile u8, @ptrCast(&scrub_buffer[offset])).*;
    scrub_sink +%= sum;
}

/// When set, the bytes of the bridge's first scratch stack after every call.
var scratch_trace: ?*std.ArrayListUnmanaged(u64) = null;

fn dispatchHook(context: ?*anyopaque, state_pointer: *anyopaque, name_pointer: [*]const u8, name_length: usize, direct: u64, has_direct: c_int) callconv(.c) c_int {
    if (scrub_enabled) scrub();
    const bridge: *Bridge = @ptrCast(@alignCast(context.?));
    const state: *State = @ptrCast(@alignCast(state_pointer));
    const handled = bridge.dispatch(state, name_pointer[0..name_length], if (has_direct != 0) direct else null);
    if (scratch_trace) |trace| {
        var hash: u64 = 0xcbf29ce484222325;
        for (0..17) |slot| hash = (hash ^ state.read64(bridge.scratch_stacks[0] + slot * 8)) *% 0x100000001b3;
        trace.append(t.allocator, hash) catch unreachable;
    }
    return if (handled) 1 else 0;
}

pub const Fixture = struct {
    state: *State,
    bridge: *Bridge,
    stubs: [kind_count]u64,
    records: usize,
    stream_end: u64,
    expected_per_pass: [kind_count]u64,

    pub fn deinit(self: *Fixture) void {
        self.bridge.forwarder.stopAsyncVulkanCommandWorker();
        self.bridge.deinit();
        t.allocator.destroy(self.bridge);
        self.state.setParallelGuestExecution(false);
        self.state.deinit();
        t.allocator.destroy(self.state);
    }
};

const Cursor = struct {
    state: *State,
    record: u64 = stream_base,
    data: u64 = data_base,
    count: usize = 0,
    expected: [kind_count]u64 = @splat(0),

    fn alloc(self: *Cursor, bytes: u64) u64 {
        const address = std.mem.alignForward(u64, self.data, 16);
        self.data = address + bytes;
        return address;
    }
    fn emit(self: *Cursor, fixture_stubs: *const [kind_count]u64, kind: Kind, registers: [4]u64, stack: [6]u64) void {
        const s = self.state;
        s.write64(self.record, fixture_stubs[@intFromEnum(kind)]);
        for (registers, 0..) |value, i| s.write64(self.record + 8 + i * 8, value);
        for (stack, 0..) |value, i| s.write64(self.record + 40 + i * 8, value);
        s.write64(self.record + 88, 0);
        self.record += record_bytes;
        self.count += 1;
        self.expected[@intFromEnum(kind)] += 1;
    }
};

fn handle(group: u64, index: u64) u64 {
    return 0xfffff500_0000_0000 | group << 24 | index;
}

fn native(group: u64, index: u64) u64 {
    return 0x7000_0000_0000 | group << 24 | index;
}

/// Build the PE state, the bridge and the forwarder's native identities, and
/// lay out `draws` draws of the eight-draw pattern as guest command records.
/// Publish a Xenia code-cache interval, as a live run does once Xenia has
/// mapped its code cache: calls to the thunks then leave through the
/// published-range edge of the translated call (`block_jit/core.zig`)
/// rather than the bootstrap one.
var publish_code_cache = false;

pub fn create(draws: usize) !Fixture {
    const s = try t.allocator.create(State);
    s.* = State.init(t.allocator);
    s.windows_runtime_enabled = true;
    s.setParallelGuestExecution(true);
    s.windows_active_guest_thread_slot = 3;
    s.windows_guest_threads[3] = .{ .status = .running, .thread_id = 43 };
    s.windows_memory_trace_step_closed.store(true, .monotonic);
    s.guest_clock.source = .host_monotonic;
    s.image_low = base;
    s.image_high = code + 0x400;
    if (publish_code_cache) {
        s.block_jit_code_cache_guest_low = base + 0x7000_0000;
        s.block_jit_code_cache_guest_high = base + 0x7001_0000;
    }

    const bridge = try t.allocator.create(Bridge);
    bridge.* = .{};
    bridge.library_token = 1;
    const f = &bridge.forwarder;
    f.guest_libraries[0] = .{ .token = 1, .virtual_vulkan = true };
    f.real_vulkan.device = @ptrFromInt(device);
    f.vulkan_async_command_worker_decided = true;
    // `ROSETTE_DRAW_STREAM_SYNC=1`: every command runs on the calling thread,
    // so a timing is the caller's route alone, not its race with the worker.
    f.vulkan_async_command_worker_enabled = std.c.getenv("ROSETTE_DRAW_STREAM_SYNC") == null;
    const rv = &f.real_vulkan;
    rv.command_buffer_map[0] = .{ .synthetic = command_buffer, .real = native_command_buffer };
    for (0..pipeline_count + compute_count) |i| rv.pipeline_map[i] = .{ .synthetic = handle(1, i), .real = native(1, i) };
    // The live table holds every graphics pipeline Xenia created, so a bind
    // finds its record part-way through it; compute pipelines (one bind in
    // four here, 21% in the supplied run) are never recorded at all.
    for (0..tracked_filler) |i| f.tracked_graphics_pipelines[i] = .{ .real = native(7, i) };
    for (0..pipeline_count) |i| f.tracked_graphics_pipelines[i * tracked_spacing + tracked_spacing / 2] = .{ .real = native(1, i), .stage_count = 2 };
    f.tracked_pipeline_lookup.invalidate();
    for (0..layout_count) |i| rv.pipeline_layout_map[i] = .{ .synthetic = handle(2, i), .real = native(2, i) };
    for (0..set_count) |i| rv.descriptor_set_map[i] = .{ .synthetic = handle(3, i), .real = native(3, i) };
    for (0..buffer_count) |i| rv.buffer_map[i] = .{ .synthetic = handle(4, i), .real = native(4, i) };
    for (0..view_count) |i| rv.image_view_map[i] = .{ .synthetic = handle(5, i), .real = native(5, i) };
    for (0..sampler_count) |i| rv.sampler_map[i] = .{ .synthetic = handle(6, i), .real = native(6, i) };
    rv.fn_ptrs.cmd_set_viewport = Driver.viewport;
    rv.fn_ptrs.cmd_set_scissor = Driver.scissor;
    rv.fn_ptrs.cmd_bind_pipeline = Driver.pipeline;
    rv.fn_ptrs.update_descriptor_sets = Driver.update;
    rv.fn_ptrs.cmd_bind_descriptor_sets = Driver.sets;
    rv.fn_ptrs.cmd_push_constants = Driver.push;
    rv.fn_ptrs.cmd_pipeline_barrier = @ptrCast(&Driver.barrier);
    rv.fn_ptrs.cmd_bind_index_buffer = Driver.index;
    rv.fn_ptrs.cmd_draw_indexed = Driver.draw;

    s.windows_graphics.hooks.native_context = bridge;
    s.windows_graphics.hooks.native_vulkan_dispatch = dispatchHook;
    var stubs: [kind_count]u64 = undefined;
    for (&stubs, 0..) |*stub, i| stub.* = s.registerWindowsImportStub("vulkan-1.dll", @as(Kind, @enumFromInt(i)).name()).?;
    for (program, 0..) |byte, i| s.write8(code + i, byte);
    s.configureWindowsExecutableRanges(&.{.{ .guest_base = code, .length = program.len }});

    var c = Cursor{ .state = s };
    const viewport = c.alloc(@sizeOf(abi.Viewport));
    s.write32(viewport + 8, @bitCast(@as(f32, 1280)));
    s.write32(viewport + 12, @bitCast(@as(f32, 720)));
    s.write32(viewport + 20, @bitCast(@as(f32, 1)));
    const scissor = c.alloc(@sizeOf(abi.Rect2D));
    s.write32(scissor + 8, 1280);
    s.write32(scissor + 12, 720);
    const push_data = c.alloc(16);
    for (0..16) |i| s.write8(push_data + i, @intCast(i + 1));
    const barrier = c.alloc(@sizeOf(abi.BufferMemoryBarrier));
    s.write32(barrier, abi.buffer_memory_barrier_structure_type);
    s.write32(barrier + 16, 0x2);
    s.write32(barrier + 20, 0x20);
    s.write32(barrier + 24, 0xffff_ffff);
    s.write32(barrier + 28, 0xffff_ffff);
    s.write64(barrier + 32, handle(4, 1));
    s.write64(barrier + 48, 4096);
    const constants_set = handle(3, set_count - 1);

    var texture_set: u64 = 0;
    for (0..draws) |draw| {
        const in_group = draw % 8;
        const cb = command_buffer;
        if (in_group == 0) {
            c.emit(&stubs, .set_viewport, .{ cb, 0, 1, viewport }, @splat(0));
            c.emit(&stubs, .set_scissor, .{ cb, 0, 1, scissor }, @splat(0));
        }
        if (in_group % 2 == 0) {
            const compute = in_group == 4;
            const pipeline = if (compute) pipeline_count + (draw / 8) % compute_count else (draw / 2) % pipeline_count;
            c.emit(&stubs, .bind_pipeline, .{ cb, @intFromBool(compute), handle(1, pipeline), 0 }, @splat(0));
        }
        if (in_group != 7) {
            // A fresh texture set: three writes, four sampled images, three
            // samplers and one uniform buffer - Xenia's ~8.5 descriptors per
            // update in the supplied run.
            texture_set = (texture_set + 1) % (set_count - 1);
            const set = handle(3, texture_set);
            const images = c.alloc(4 * @sizeOf(abi.DescriptorImageInfo));
            for (0..4) |i| {
                s.write64(images + i * 24 + 8, handle(5, (draw * 4 + i) % view_count));
                s.write32(images + i * 24 + 16, 5);
            }
            const samplers = c.alloc(3 * @sizeOf(abi.DescriptorImageInfo));
            for (0..3) |i| s.write64(samplers + i * 24, handle(6, (draw + i) % sampler_count));
            const uniform = c.alloc(@sizeOf(abi.DescriptorBufferInfo));
            s.write64(uniform, handle(4, draw % buffer_count));
            s.write64(uniform + 16, 256);
            const writes = c.alloc(3 * @sizeOf(abi.WriteDescriptorSet));
            const shapes = [_]struct { binding: u32, count: u32, kind: u32, images: u64, buffers: u64 }{
                .{ .binding = 0, .count = 4, .kind = 2, .images = images, .buffers = 0 },
                .{ .binding = 1, .count = 3, .kind = 0, .images = samplers, .buffers = 0 },
                .{ .binding = 2, .count = 1, .kind = 6, .images = 0, .buffers = uniform },
            };
            for (shapes, 0..) |shape, i| {
                const write = writes + i * 64;
                s.write32(write, abi.WriteDescriptorSet_structure_type);
                s.write64(write + 16, set);
                s.write32(write + 24, shape.binding);
                s.write32(write + 32, shape.count);
                s.write32(write + 36, shape.kind);
                s.write64(write + 40, shape.images);
                s.write64(write + 48, shape.buffers);
            }
            c.emit(&stubs, .update_descriptor_sets, .{ device, 3, writes, 0 }, .{ 0, 0, 0, 0, 0, 0 });
            const bound = c.alloc(16);
            s.write64(bound, constants_set);
            s.write64(bound + 8, set);
            c.emit(&stubs, .bind_descriptor_sets, .{ cb, 0, handle(2, draw % layout_count), 0 }, .{ 2, bound, 0, 0, 0, 0 });
        }
        if (in_group == 1 or in_group == 5) {
            const bound = c.alloc(16);
            s.write64(bound, constants_set);
            s.write64(bound + 8, handle(3, (draw * 7) % (set_count - 1)));
            c.emit(&stubs, .bind_descriptor_sets, .{ cb, 0, handle(2, draw % layout_count), 0 }, .{ 2, bound, 0, 0, 0, 0 });
        }
        if (in_group == 3 or in_group == 6) {
            c.emit(&stubs, .push_constants, .{ cb, handle(2, 0), 0x10, 0 }, .{ 16, push_data, 0, 0, 0, 0 });
        }
        if (in_group == 2 or in_group == 6) {
            c.emit(&stubs, .pipeline_barrier, .{ cb, 0x1000, 0x8, 0 }, .{ 0, 0, 1, barrier, 0, 0 });
        }
        c.emit(&stubs, .bind_index_buffer, .{ cb, handle(4, draw % buffer_count), (draw % 16) * 1024, 0 }, @splat(0));
        c.emit(&stubs, .draw_indexed, .{ cb, @intCast(3 * (draw % 200 + 1)), 1, @intCast(draw * 3) }, .{ 0, 0, 0, 0, 0, 0 });
    }
    std.debug.assert(c.record <= data_base);
    return .{
        .state = s,
        .bridge = bridge,
        .stubs = stubs,
        .records = c.count,
        .stream_end = c.record,
        .expected_per_pass = c.expected,
    };
}

pub const Run = struct {
    calls: u64,
    cpu_ns: u64,
    wall_ns: u64,
    process_cpu_ns: u64,
    steps: u64,
};

/// Replay `passes` complete passes over the stream and verify that every
/// call reached the stub driver, unchanged, before returning the CPU time.
pub fn run(fixture: *Fixture, passes: u64) !Run {
    const s = fixture.state;
    const calls = passes * fixture.records;
    s.regs = .{ .rip = code, .rsp = stack_top - 0x200, .rsi = stream_base, .rdi = fixture.stream_end, .r12 = stream_base, .rbx = calls, .r13 = 0x1313, .r14 = 0x1414, .r15 = 0x1515, .rbp = 0xb0b0, .rflags = 0x246 };
    Driver.reset();
    const started_process = processCpu();
    const started_cpu = cpu();
    const started_wall = wall();
    var steps: u64 = 0;
    while (s.regs.rip != done_rip and steps < calls * 64 + 1000) : (steps += 1) {
        try t.expect(s.step());
    }
    const elapsed_cpu = cpu() - started_cpu;
    if (fixture.bridge.forwarder.vulkan_async_command_worker) |worker| worker.drain();
    const elapsed_wall = wall() - started_wall;
    const elapsed_process = processCpu() - started_process;
    try t.expectEqual(done_rip, s.regs.rip);
    try t.expectEqual(@as(u64, 0), s.regs.rbx);
    try t.expectEqual(@as(u64, 0x1313), s.regs.r13);
    try t.expectEqual(@as(u64, 0xb0b0), s.regs.rbp);
    try t.expectEqual(stream_base, s.regs.r12);
    for (0..kind_count) |kind| try t.expectEqual(passes * fixture.expected_per_pass[kind], Driver.calls[kind]);
    try t.expectEqual(@as(u64, 0), Driver.errors);
    return .{ .calls = calls, .cpu_ns = elapsed_cpu, .wall_ns = elapsed_wall, .process_cpu_ns = elapsed_process, .steps = steps };
}

/// The internal controls this replay compares; `false` is the original
/// implementation of each.
pub const Control = enum { fifo_handoff, pipeline_memo, trace_setting, scratch_slots, duration_clocks, vulkan_stub_early_out, vulkan_call_lane, route_memo };

pub fn setControl(control: Control, on: bool) void {
    switch (control) {
        .fifo_handoff => @import("gpu").vulkan.async_command_worker.handoff.enabled = on,
        .pipeline_memo => @import("dyld").dynamic_library_forwarder.forwarder_pipeline_lookup.enabled = on,
        .trace_setting => @import("dyld").dynamic_library_forwarder.vulkan_dispatch_trace_cached = on,
        .scratch_slots => forwarder_module.bridge_route.scratch_enabled = on,
        .duration_clocks => {
            forwarder_module.bridge_route.fast_clock = on;
            P.__ProcessInternals._concurrency.duration_clock.enabled = on;
        },
        .vulkan_stub_early_out => P.__ProcessInternals._register_import.vulkan_stub_early_out = on,
        .vulkan_call_lane => P.__ProcessInternals._vulkan_call_lane.enabled = on,
        .route_memo => forwarder_module.route_memo.enabled = on,
    }
}

pub fn setControls(on: bool) void {
    inline for (std.meta.fields(Control)) |field| setControl(@enumFromInt(field.value), on);
}

fn workerStats(fixture: *Fixture) @import("gpu").vulkan.async_command_worker.Stats {
    const worker = fixture.bridge.forwarder.vulkan_async_command_worker orelse return std.mem.zeroes(@import("gpu").vulkan.async_command_worker.Stats);
    return worker.stats();
}

test "Xenia draw stream reaches the stub driver through the production PE Vulkan route" {
    defer setControls(true);
    for ([_]bool{ false, true }) |on| {
        setControls(on);
        var fixture = try create(64);
        defer fixture.deinit();
        const lane = P.__ProcessInternals._vulkan_call_lane;
        const lane_before = lane.completedCalls();
        const first = try run(&fixture, 2);
        const checksum = Driver.checksum;
        _ = try run(&fixture, 2);
        try t.expectEqual(checksum, Driver.checksum);
        try t.expect(first.calls == 2 * fixture.records);
        // Every call in the stream records commands: on, the translated
        // calls complete in place once the loop is hot; off, none do.
        const lane_calls = lane.completedCalls() - lane_before;
        if (on) try t.expect(lane_calls > 3 * fixture.records) else try t.expectEqual(@as(u64, 0), lane_calls);
    }
}

test "Xenia draw stream with a published code cache completes every thunk call in place, exactly as interpreted" {
    defer setControls(true);
    publish_code_cache = true;
    defer publish_code_cache = false;
    const lane = P.__ProcessInternals._vulkan_call_lane;
    var checksums: [2]u64 = undefined;
    for ([_]bool{ false, true }, 0..) |on, index| {
        setControl(.vulkan_call_lane, on);
        var fixture = try create(64);
        defer fixture.deinit();
        const before = lane.completedCalls();
        const result = try run(&fixture, 3);
        checksums[index] = Driver.checksum;
        try t.expectEqual(3 * fixture.records, result.calls);
        const completed = lane.completedCalls() - before;
        if (on) try t.expect(completed > 2 * fixture.records) else try t.expectEqual(@as(u64, 0), completed);
    }
    try t.expectEqual(checksums[0], checksums[1]);
}

test "Xenia draw stream leaves the scratch stack byte-identical with every control off and on" {
    defer setControls(true);
    var traces: [2]std.ArrayListUnmanaged(u64) = .{ .empty, .empty };
    defer for (&traces) |*trace| trace.deinit(t.allocator);
    defer scratch_trace = null;
    for ([_]bool{ false, true }, 0..) |on, index| {
        setControls(on);
        var fixture = try create(64);
        defer fixture.deinit();
        scratch_trace = &traces[index];
        _ = try run(&fixture, 3);
        scratch_trace = null;
    }
    try t.expect(traces[0].items.len > 900);
    try t.expectEqualSlices(u64, traces[0].items, traces[1].items);
}

test "Xenia draw stream CPU comparison (ROSETTE_DRAW_STREAM_BENCH=1)" {
    if (std.c.getenv("ROSETTE_DRAW_STREAM_BENCH") == null) return;
    defer setControls(true);
    var fixture = try create(64);
    defer fixture.deinit();
    _ = try run(&fixture, 50);
    if (std.c.getenv("ROSETTE_DRAW_STREAM_PROFILE")) |mode| {
        // A long single-mode replay for an external sampling profiler.
        setControls(std.mem.eql(u8, std.mem.span(mode), "on"));
        // `ROSETTE_DRAW_STREAM_COLD=1`: the cold profile's scrub on every
        // fourth call, the same on either side of a comparison.
        @memset(&scrub_buffer, 1);
        scrub_enabled = std.c.getenv("ROSETTE_DRAW_STREAM_COLD") != null;
        defer scrub_enabled = false;
        const passes: u64 = if (std.c.getenv("ROSETTE_DRAW_STREAM_PASSES")) |raw| std.fmt.parseInt(u64, std.mem.span(raw), 10) catch 6000 else 6000;
        const result = try run(&fixture, if (scrub_enabled) passes / 4 else passes);
        std.debug.print("draw_stream profile_run calls={d} cpu_ns={d} cold={}\n", .{ result.calls, result.cpu_ns, scrub_enabled });
        return;
    }
    var references: [2]?u64 = .{ null, null };
    @memset(&scrub_buffer, 1);
    // The scrub alone, so the cold profile can be reported net of it.
    for (0..3) |_| {
        scrub_calls = 0;
        const scrub_started = cpu();
        for (0..100 * fixture.records) |_| scrub();
        std.debug.print("draw_stream scrub_calibration calls={d} cpu_ns={d}\n", .{ 100 * fixture.records, cpu() - scrub_started });
    }
    defer scrub_enabled = false;
    for ([_]bool{ false, true }) |cold| for (0..7) |pair| {
        scrub_enabled = cold;
        for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |on| {
            setControls(on);
            _ = try run(&fixture, 20);
            const before = workerStats(&fixture);
            const result = try run(&fixture, if (cold) 100 else 400);
            const after = workerStats(&fixture);
            const reference = &references[@intFromBool(cold)];
            if (reference.*) |value| try t.expectEqual(value, Driver.checksum) else reference.* = Driver.checksum;
            std.debug.print("draw_stream profile={s} pair={d} enabled={} calls={d} cpu_ns={d} wall_ns={d} process_cpu_ns={d} steps={d} signals={d} parks={d} broadcasts={d} drain_spin_hits={d} spin_pickups={d} batches={d} saturated={d} checksum={d}\n", .{
                if (cold) "cold" else "hot",                                pair,
                on,                                                         result.calls,
                result.cpu_ns,                                              result.wall_ns,
                result.process_cpu_ns,                                      result.steps,
                after.work_signals - before.work_signals,                   after.parks - before.parks,
                after.drain_broadcasts - before.drain_broadcasts,           after.drain_spin_hits - before.drain_spin_hits,
                after.spin_pickups - before.spin_pickups,                   after.batches - before.batches,
                after.saturated_submissions - before.saturated_submissions, Driver.checksum,
            });
        }
    };
}

test "Xenia draw stream per-change CPU breakdown (ROSETTE_DRAW_STREAM_ABLATION=1)" {
    if (std.c.getenv("ROSETTE_DRAW_STREAM_ABLATION") == null) return;
    // Each change's own contribution: everything on, against everything on
    // except that one change. Contributions overlap, so they need not add
    // up to the all-off comparison.
    defer setControls(true);
    var fixture = try create(64);
    defer fixture.deinit();
    setControls(true);
    _ = try run(&fixture, 50);
    var reference: ?u64 = null;
    // `ROSETTE_DRAW_STREAM_ONLY=<control>` measures one change.
    const only: ?[]const u8 = if (std.c.getenv("ROSETTE_DRAW_STREAM_ONLY")) |raw| std.mem.span(raw) else null;
    inline for (std.meta.fields(Control)) |field| {
        const control: Control = @enumFromInt(field.value);
        if (only == null or std.mem.eql(u8, only.?, field.name)) for (0..7) |pair| {
            for (if (pair % 2 == 0) [_]bool{ false, true } else [_]bool{ true, false }) |without| {
                setControls(true);
                setControl(control, !without);
                _ = try run(&fixture, 20);
                const before = workerStats(&fixture);
                const result = try run(&fixture, 300);
                const after = workerStats(&fixture);
                if (reference) |value| try t.expectEqual(value, Driver.checksum) else reference = Driver.checksum;
                std.debug.print("draw_stream ablation={s} pair={d} without={} calls={d} cpu_ns={d} wall_ns={d} process_cpu_ns={d} saturated={d} drain_spin_hits={d} parks={d} checksum={d}\n", .{ field.name, pair, without, result.calls, result.cpu_ns, result.wall_ns, result.process_cpu_ns, after.saturated_submissions - before.saturated_submissions, after.drain_spin_hits - before.drain_spin_hits, after.parks - before.parks, Driver.checksum });
            }
        };
    }
}
