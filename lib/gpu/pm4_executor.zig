//! Stateful PM4 command processing for the Xenos register aperture.
//!
//! `pm4.zig` owns packet arithmetic.  This module owns the next layer: bounded
//! packet walking, register writes, draw extraction, event completion, and the
//! guest swap message.  It never touches guest memory itself; callers provide a
//! dword span that has already passed their memory-translation checks.

const std = @import("std");
const pm4 = @import("pm4.zig");
const regs = @import("xenos_registers.zig");

pub const Failure = enum(u8) {
    truncated_packet,
    invalid_packet,
    wait_condition_failed,

    pub fn label(self: Failure) []const u8 {
        return switch (self) {
            .truncated_packet => "truncated_packet",
            .invalid_packet => "invalid_packet",
            .wait_condition_failed => "wait_condition_failed",
        };
    }
};

pub const Error = error{
    truncated_packet,
    invalid_packet,
    wait_condition_failed,
};

pub const Draw = struct {
    indexed: bool = false,
    indirect: bool = false,
    primitive: regs.PrimitiveType = .triangle_list,
    source: regs.SourceSelect = .auto_index,
    major_mode_explicit: bool = false,
    index_format: regs.IndexFormat = .uint16,
    not_end_of_pipe: bool = false,
    count: u32 = 0,
    instance_count: u32 = 1,
    index_offset: i32 = 0,
    index_address: u32 = 0,
    index_size_words: u32 = 0,
    index_endian: regs.Endian = .none,
    viz_query_condition: u32 = 0,
    immediate_index_dwords: u32 = 0,
};

pub const Event = union(enum) {
    event_write: struct { event_id: u32, value: u32 },
    event_write_shd: struct { event_id: u32, address: u32, value: u32 },
    event_write_cfl: struct { event_id: u32 },
    event_write_ext: struct { event_id: u32, address: u32 },
    event_write_zpd: struct { event_id: u32, sample_count_address: u32 },
    interrupt: u32,
    memory_write: struct { address: u32, value: u32, endian: u2 },
    wait_deferred: struct { address: u32, reference: u32, mask: u32, memory: bool },
    indirect_buffer: struct { address: u32, size_dwords: u32 },
    swap: pm4.SwapDescription,
    read_pointer_writeback: u32,
};

pub const Callback = *const fn (context: *anyopaque, event: Event) void;
pub const DrawCallback = *const fn (context: *anyopaque, draw: Draw) void;
pub const MemoryReadCallback = *const fn (context: *anyopaque, address: u32) ?u32;
pub const MemoryWriteCallback = *const fn (context: *anyopaque, address: u32, value: u32, endian: u2) bool;
pub const IndirectBufferCallback = *const fn (context: *anyopaque, address: u32, size_dwords: u32) void;

pub const Executor = struct {
    register_file: regs.RegisterFile = .{},
    packet_count: u64 = 0,
    type0_count: u64 = 0,
    type2_count: u64 = 0,
    type3_count: u64 = 0,
    draw_count: u64 = 0,
    event_count: u64 = 0,
    swap_count: u64 = 0,
    unknown_opcode_count: u64 = 0,
    invalid_packet_count: u64 = 0,
    deferred_wait_count: u64 = 0,
    deferred_memory_count: u64 = 0,
    indirect_buffer_count: u64 = 0,
    register_rmw_count: u64 = 0,
    conditional_write_count: u64 = 0,
    predicated_skip_count: u64 = 0,
    bin_mask_updates: u64 = 0,
    bin_select_updates: u64 = 0,
    interrupt_count: u64 = 0,
    conditional_execute_count: u64 = 0,
    conditional_skip_count: u64 = 0,
    memory_counter_write_count: u64 = 0,
    surface_base_update_count: u64 = 0,
    viz_query_count: u64 = 0,
    state_invalidate_count: u64 = 0,
    context_update_count: u64 = 0,
    wait_for_idle_count: u64 = 0,
    me_init_count: u64 = 0,
    shader_constant_write_count: u64 = 0,
    shader_memory_load_count: u64 = 0,
    shader_dwords_loaded: u64 = 0,
    shader_load_count: u64 = 0,
    shader_immediate_load_count: u64 = 0,
    unsupported_immediate_draw_count: u64 = 0,
    program_counter: u32 = 0,
    conditional_skip_dwords: u32 = 0,
    bin_mask: u64 = 0,
    bin_select: u64 = 0,
    bin_base_offset: u32 = 0,
    last_invalidate_mask: u32 = 0,
    last_context_update: u32 = 0,
    last_me_init_dwords: u32 = 0,
    last_shader_type: u2 = 0,
    last_shader_address: u32 = 0,
    last_shader_start: u32 = 0,
    last_shader_size: u32 = 0,
    /// Bounded copy of the most recently loaded shader words. Xenia's active
    /// Mac command processor reads IM_LOAD source words from guest memory and
    /// hands them to its shader translator; retaining the same words lets the
    /// Rosette fallback/diagnostic translator inspect the actual program
    /// instead of only recording its address and range.
    last_shader_words: [2048]u32 = [_]u32{0} ** 2048,
    last_shader_word_count: u32 = 0,
    /// Xenia's Mac command processor uses a bounded synthetic occlusion
    /// sample count for EVENT_WRITE_ZPD.  Keep the same rolling value so a
    /// title that issues begin/end visibility queries observes a completed
    /// query rather than an untouched structure.
    occlusion_samples: u32 = 100,
    completion_counter: u32 = 0,
    last_error: ?Failure = null,
    last_draw: ?Draw = null,
    last_swap: ?pm4.SwapDescription = null,
    callback_context: ?*anyopaque = null,
    event_callback: ?Callback = null,
    draw_callback: ?DrawCallback = null,
    memory_read_context: ?*anyopaque = null,
    memory_read_callback: ?MemoryReadCallback = null,
    memory_write_context: ?*anyopaque = null,
    memory_write_callback: ?MemoryWriteCallback = null,
    indirect_buffer_context: ?*anyopaque = null,
    indirect_buffer_callback: ?IndirectBufferCallback = null,

    pub fn execute(self: *Executor, dwords: []const u32) Error!void {
        var index: usize = 0;
        while (index < dwords.len) {
            self.program_counter +%= 1;
            self.register_file.write(regs.CP_PROG_COUNTER, self.program_counter);
            const header = pm4.decodeHeader(dwords[index]);
            self.packet_count +%= 1;
            const total = header.totalDwords();
            if (total == 0 or index + total > dwords.len) {
                self.invalid_packet_count +%= 1;
                self.last_error = .truncated_packet;
                return error.truncated_packet;
            }
            const payload = dwords[index + 1 .. index + total];
            switch (header.kind) {
                .type0 => self.executeType0(header, payload),
                .type1 => {
                    if (payload.len != 2) return self.fail(.invalid_packet);
                    self.register_file.write(header.register_index, payload[0]);
                    self.register_file.write(header.register_index_2, payload[1]);
                },
                .type2 => self.type2_count +%= 1,
                .type3 => try self.executeType3(header.opcode, payload, dwords[index .. index + total], header.predicated),
            }
            index += total;
            if (self.conditional_skip_dwords != 0) {
                const skip = @min(self.conditional_skip_dwords, @as(u32, @intCast(dwords.len - index)));
                index += @as(usize, @intCast(skip));
                self.conditional_skip_dwords = 0;
            }
        }
        self.last_error = null;
    }

    fn executeType0(self: *Executor, header: pm4.Header, payload: []const u32) void {
        self.type0_count +%= 1;
        if (header.one_register) {
            for (payload) |value| self.register_file.write(header.register_index, value);
        } else {
            self.register_file.writeRange(header.register_index, payload);
        }
    }

    fn executeType3(self: *Executor, opcode: pm4.Type3Opcode, payload: []const u32, packet: []const u32, predicated: bool) Error!void {
        self.type3_count +%= 1;
        const raw = @as(u32, @intFromEnum(opcode));
        // Xenos predication is the bin check performed by Xenia's command
        // processor: a packet runs only when at least one selected bin is
        // enabled. XE_SWAP is never executed predicated, even if its bit is
        // set in a malformed or stale ring packet.
        if (predicated and (raw == 0x64 or (self.bin_select & self.bin_mask) == 0)) {
            self.predicated_skip_count +%= 1;
            return;
        }
        switch (raw) {
            0x10 => {}, // NOP
            0x26 => self.executeWaitForIdle(payload),
            0x2C, 0x2E, 0x4A, 0x5C, 0x5D => {},
            0x2D => self.executeSetConstant(payload),
            0x2F => self.executeLoadAluConstant(payload),
            0x23 => self.executeVizQuery(payload),
            0x27 => self.executeImLoad(payload),
            0x2B => self.executeImLoadImmediate(payload),
            0x3B => self.executeInvalidateState(payload),
            0x48 => self.executeMeInit(payload),
            0x55 => self.executeSetConstant2(payload),
            0x56 => self.executeSetShaderConstants(payload),
            0x5E => self.executeContextUpdate(payload),
            0x21 => self.executeRegisterRmw(payload),
            0x22, 0x34, 0x35, 0x36 => self.executeDraw(raw, payload),
            0x25 => {},
            0x3C, 0x52, 0x53 => try self.executeWaitRegMem(payload),
            0x3D => self.executeMemoryWrite(payload),
            0x4F => self.executeMemoryWriteCounter(payload),
            0x3E => self.executeRegisterToMemory(payload),
            0x3F, 0x37 => self.executeIndirectBuffer(payload),
            0x44 => self.executeConditionalExecute(payload),
            0x45 => self.executeConditionalWrite(payload),
            0x46 => self.executeEventWrite(payload),
            0x58 => self.executeEventWriteShd(payload),
            0x59 => self.executeEventWriteCfl(payload),
            0x5A => self.executeEventWriteExt(payload),
            0x5B => self.executeEventWriteZpd(payload),
            0x50 => self.executeBinMask(payload),
            0x51 => self.executeBinSelect(payload),
            0x4B => self.executeBinBaseOffset(payload),
            0x54 => {
                self.interrupt_count +%= 1;
                self.emitEvent(.{ .interrupt = payloadValue(payload, 0) });
            },
            0x60, 0x61 => self.executeBinMaskPart(raw, payload),
            0x62, 0x63 => self.executeBinSelectPart(raw, payload),
            0x64 => {
                const swap = pm4.decodeSwapSequence(packet) orelse return self.fail(.invalid_packet);
                self.swap_count +%= 1;
                self.last_swap = swap;
                self.emitEvent(.{ .swap = swap });
            },
            else => self.unknown_opcode_count +%= 1,
        }
    }

    fn executeBinMask(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        self.bin_mask = (@as(u64, payload[0]) << 32) | payload[1];
        self.bin_mask_updates +%= 1;
    }

    fn executeBinSelect(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        self.bin_select = (@as(u64, payload[0]) << 32) | payload[1];
        self.bin_select_updates +%= 1;
    }

    fn executeBinMaskPart(self: *Executor, opcode: u32, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const value = @as(u64, payload[0]);
        self.bin_mask = if (opcode == 0x60)
            (self.bin_mask & 0xFFFF_FFFF_0000_0000) | value
        else
            (self.bin_mask & 0x0000_0000_FFFF_FFFF) | (value << 32);
        self.bin_mask_updates +%= 1;
    }

    fn executeBinSelectPart(self: *Executor, opcode: u32, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const value = @as(u64, payload[0]);
        self.bin_select = if (opcode == 0x62)
            (self.bin_select & 0xFFFF_FFFF_0000_0000) | value
        else
            (self.bin_select & 0x0000_0000_FFFF_FFFF) | (value << 32);
        self.bin_select_updates +%= 1;
    }

    fn executeSetConstant(self: *Executor, payload: []const u32) void {
        if (payload.len == 0) return;
        // The low eleven bits select a constant and bits 16..23 select the
        // constant bank.  Treating the whole dword as a register (the old
        // approximation) writes shader constants into unrelated RB state.
        const offset_type = payload[0];
        const index = offset_type & 0x7FF;
        const kind = (offset_type >> 16) & 0xFF;
        const base = constantBankBase(kind) orelse {
            self.recordInvalidPacket();
            return;
        };
        const start_value = base +| index;
        if (start_value > std.math.maxInt(regs.Register)) return;
        const start: regs.Register = @intCast(start_value);
        if (payload.len > 1) {
            self.register_file.writeRange(start, payload[1..]);
            self.shader_constant_write_count +%= payload.len - 1;
        }
    }

    fn executeSetConstant2(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const start = payload[0] & 0xFFFF;
        self.register_file.writeRange(@intCast(start), payload[1..]);
        self.shader_constant_write_count +%= payload.len - 1;
    }

    fn executeSetShaderConstants(self: *Executor, payload: []const u32) void {
        // SET_SHADER_CONSTANTS uses the same absolute register index as
        // SET_CONSTANT2; Xenia's ring writer does not apply a bank multiplier.
        self.executeSetConstant2(payload);
    }

    fn executeLoadAluConstant(self: *Executor, payload: []const u32) void {
        if (payload.len < 3) {
            self.recordInvalidPacket();
            return;
        }
        const address = payload[0] & 0x3FFF_FFFC;
        const offset_type = payload[1];
        const index = offset_type & 0x7FF;
        const kind = (offset_type >> 16) & 0xFF;
        const base = constantBankBase(kind) orelse {
            self.recordInvalidPacket();
            return;
        };
        const size = payload[2] & 0xFFF;
        self.shader_memory_load_count +%= 1;
        for (0..size) |offset| {
            const register_value = base +| index +| @as(u32, @intCast(offset));
            if (register_value > std.math.maxInt(regs.Register)) break;
            const value = self.readMemory(address +% @as(u32, @intCast(offset * 4))) orelse break;
            self.register_file.write(@intCast(register_value), value);
            self.shader_dwords_loaded +%= 1;
        }
    }

    fn executeVizQuery(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const query = payload[0];
        const query_id = query & 0x3F;
        const ending = (query & 0x100) != 0;
        self.viz_query_count +%= 1;
        self.register_file.write(regs.VGT_EVENT_INITIATOR, if (ending) 8 else 7);
        if (ending) {
            if (query_id < 32) {
                const status = self.register_file.peek(regs.PA_SC_VIZ_QUERY_STATUS_0);
                self.register_file.write(regs.PA_SC_VIZ_QUERY_STATUS_0, status | (@as(u32, 1) << @as(u5, @intCast(query_id))));
            } else {
                const status = self.register_file.peek(regs.PA_SC_VIZ_QUERY_STATUS_1);
                self.register_file.write(regs.PA_SC_VIZ_QUERY_STATUS_1, status | (@as(u32, 1) << @as(u5, @intCast(query_id - 32))));
            }
        }
    }

    fn executeInvalidateState(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        self.state_invalidate_count +%= 1;
        self.last_invalidate_mask = payload[0];
    }

    fn executeWaitForIdle(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        self.wait_for_idle_count +%= 1;
    }

    fn executeContextUpdate(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        self.context_update_count +%= 1;
        self.last_context_update = payload[0];
    }

    fn executeMeInit(self: *Executor, payload: []const u32) void {
        self.me_init_count +%= 1;
        self.last_me_init_dwords = @intCast(@min(payload.len, std.math.maxInt(u32)));
    }

    fn executeImLoad(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const address_type = payload[0];
        const start_size = payload[1];
        self.shader_load_count +%= 1;
        self.last_shader_type = @truncate(address_type & 0x3);
        self.last_shader_address = address_type & 0x3FFF_FFFC;
        self.last_shader_start = start_size >> 16;
        self.last_shader_size = start_size & 0xFFFF;
        self.last_shader_word_count = 0;
        const requested = @min(self.last_shader_size, @as(u32, @intCast(self.last_shader_words.len)));
        if (self.memory_read_callback) |callback| {
            for (0..@as(usize, @intCast(requested))) |index| {
                const word_index = self.last_shader_start + @as(u32, @intCast(index));
                const address = self.last_shader_address +% (word_index * 4);
                const word = callback(self.memory_read_context orelse @ptrCast(@constCast(&self.register_file)), address) orelse break;
                self.last_shader_words[index] = word;
                self.last_shader_word_count +%= 1;
            }
            self.shader_dwords_loaded +%= self.last_shader_word_count;
        }
    }

    fn executeImLoadImmediate(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        self.shader_immediate_load_count +%= 1;
        self.last_shader_type = @truncate(payload[0] & 0x3);
        self.last_shader_address = 0;
        self.last_shader_start = payload[1] >> 16;
        self.last_shader_size = @min(payload[1] & 0xFFFF, @as(u32, @intCast(payload.len - 2)));
        self.last_shader_word_count = @min(self.last_shader_size, @as(u32, @intCast(self.last_shader_words.len)));
        for (0..@as(usize, @intCast(self.last_shader_word_count))) |index| {
            self.last_shader_words[index] = payload[2 + index];
        }
        self.shader_dwords_loaded +%= self.last_shader_word_count;
    }

    fn executeBinBaseOffset(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        self.bin_base_offset = payload[0];
        self.surface_base_update_count +%= 1;
    }

    fn executeDraw(self: *Executor, opcode: u32, payload: []const u32) void {
        const initiator_index: usize = if (opcode == 0x22 or opcode == 0x34) 1 else 0;
        if (payload.len <= initiator_index) {
            self.recordInvalidPacket();
            return;
        }
        const initiator_raw = payloadValue(payload, initiator_index);
        self.register_file.write(regs.VGT_DRAW_INITIATOR, initiator_raw);
        const initiator = regs.DrawInitiator.decode(initiator_raw);
        const has_viz_token = opcode == 0x22 or opcode == 0x34;
        if (initiator.source == .dma) {
            // DRAW_INDX carries the visualization token before the same
            // initiator/base/size triplet used by Xenia's command processor.
            // DMA base and size are consumed only for a DMA-source draw: an
            // immediate or auto-index packet has no DMA fields at these
            // positions, and reading them corrupts the next draw's index state.
            const dma_base_index = initiator_index + 1;
            const dma_size_index = initiator_index + 2;
            if (payload.len <= dma_size_index) {
                self.recordInvalidPacket();
                return;
            }
            self.register_file.write(regs.VGT_DMA_BASE, payload[dma_base_index]);
            self.register_file.write(regs.VGT_DMA_SIZE, payload[dma_size_index]);
        } else if (initiator.source == .immediate) {
            // The active Xenia Mac implementation deliberately logs and drops
            // immediate-index draws.  Keep this observable without sending a
            // false draw-complete event into the guest.
            self.unsupported_immediate_draw_count +%= 1;
            return;
        }
        const index_buffer = self.register_file.indexBuffer();
        const indexed = initiator.source == .dma;
        const draw = Draw{
            .indexed = indexed,
            .indirect = false,
            .primitive = initiator.primitive,
            .source = initiator.source,
            .major_mode_explicit = initiator.major_mode_explicit,
            .index_format = initiator.index_format,
            .not_end_of_pipe = initiator.not_end_of_pipe,
            .count = initiator.index_count,
            .index_offset = self.register_file.indexOffset(),
            .index_address = if (indexed) index_buffer.address_bytes else 0,
            .index_size_words = if (indexed) index_buffer.num_words else 0,
            .index_endian = if (indexed) index_buffer.endian else .none,
            .viz_query_condition = if (has_viz_token) payloadValue(payload, 0) else 0,
            .immediate_index_dwords = if (initiator.source == .immediate)
                @intCast(payload.len - initiator_index - 1)
            else
                0,
        };
        self.draw_count +%= 1;
        self.last_draw = draw;
        if (self.draw_callback) |callback| callback(self.callback_context orelse @ptrCast(@constCast(&self.register_file)), draw);
    }

    fn executeWaitRegMem(self: *Executor, payload: []const u32) Error!void {
        if (payload.len < 4) return self.fail(.invalid_packet);
        const wait_info = payload[0];
        const address = payload[1];
        const reference = payload[2];
        const mask = payload[3];
        const memory = (wait_info & 0x10) != 0;
        const relation = @as(u3, @truncate(wait_info));
        var value: ?u32 = null;
        if (memory) {
            if (self.memory_read_callback) |callback| {
                // Preserve the low address bits: Xenos uses them to select
                // the GPU endian transform for the dword at the aligned
                // physical address.
                value = callback(self.memory_read_context orelse @ptrCast(@constCast(&self.register_file)), address);
            }
        } else if (address < regs.register_count) {
            value = self.register_file.peek(@intCast(address));
        }
        if (value) |actual| {
            if (matchesWait(actual & mask, reference, relation)) return;
        }
        self.deferred_wait_count +%= 1;
        self.emitEvent(.{ .wait_deferred = .{ .address = address, .reference = reference, .mask = mask, .memory = memory } });
    }

    fn executeRegisterRmw(self: *Executor, payload: []const u32) void {
        if (payload.len < 3) {
            self.recordInvalidPacket();
            return;
        }
        const rmw_info = payload[0];
        const register = @as(regs.Register, @intCast(rmw_info & 0x1FFF));
        var value = self.register_file.peek(register);
        value &= if ((rmw_info & (1 << 31)) != 0)
            self.register_file.peek(@intCast(payload[1] & 0x1FFF))
        else
            payload[1];
        value |= if ((rmw_info & (1 << 30)) != 0)
            self.register_file.peek(@intCast(payload[2] & 0x1FFF))
        else
            payload[2];
        self.register_file.write(register, value);
        self.register_rmw_count +%= 1;
    }

    fn executeMemoryWrite(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const initial_address = payload[0];
        for (payload[1..], 0..) |value, offset| {
            const encoded_address = initial_address +% @as(u32, @intCast(offset * 4));
            self.writeMemory(encoded_address, value);
        }
    }

    fn executeMemoryWriteCounter(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        self.memory_counter_write_count +%= 1;
        self.writeMemory(payload[0], self.register_file.peek(regs.CP_PROG_COUNTER));
    }

    fn executeEventWrite(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const initiator = payload[0];
        const event_id = initiator & 0x3F;
        // EVENT_WRITE with a one-dword payload is only an event initiator
        // writeback.  Extra payload dwords are retained in the event value for
        // diagnostics, but are not treated as a guest memory write: Xenia's
        // Mac implementation deliberately leaves that form empty.
        self.register_file.write(regs.VGT_EVENT_INITIATOR, event_id);
        self.emitEvent(.{ .event_write = .{ .event_id = event_id, .value = payloadValue(payload, 1) } });
    }

    fn executeEventWriteShd(self: *Executor, payload: []const u32) void {
        if (payload.len < 3) {
            self.recordInvalidPacket();
            return;
        }
        const initiator = payload[0];
        const event_id = initiator & 0x3F;
        const address = payload[1];
        const value = if ((initiator & 0x8000_0000) != 0) blk: {
            self.completion_counter +%= 1;
            const counter = self.completion_counter;
            break :blk counter;
        } else payload[2];
        self.register_file.write(regs.VGT_EVENT_INITIATOR, event_id);
        // This writeback is the completion fence consumed by the guest.  The
        // event remains visible as a diagnostic, but the memory commit must
        // happen through the same endian-aware callback as MEM_WRITE and
        // REG_TO_MEM so WAIT_REG_MEM can observe it on the next poll.
        self.writeMemory(address, value);
        self.emitEvent(.{ .event_write_shd = .{ .event_id = event_id, .address = address, .value = value } });
    }

    fn executeEventWriteCfl(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const event_id = payload[0] & 0x3F;
        self.register_file.write(regs.VGT_EVENT_INITIATOR, event_id);
        self.emitEvent(.{ .event_write_cfl = .{ .event_id = event_id } });
    }

    fn executeEventWriteExt(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const initiator = payload[0];
        const event_id = initiator & 0x3F;
        const address = payload[1];
        self.register_file.write(regs.VGT_EVENT_INITIATOR, event_id);

        // Xenia writes six 16-bit extents as three dwords.  The low half of
        // each dword is written first, and the address low bits select the
        // Xenos 8-in-16 endian transform.  Sending the semantic values through
        // writeMemory preserves that ABI for both real guest memory and tests.
        const extent_words = [_]u32{
            (2048 << 16) | 0,
            (2048 << 16) | 0,
            (1 << 16) | 0,
        };
        for (extent_words, 0..) |word, index| {
            self.writeMemory(address +% @as(u32, @intCast(index * 4)), word);
        }
        self.emitEvent(.{ .event_write_ext = .{ .event_id = event_id, .address = address } });
    }

    fn executeEventWriteZpd(self: *Executor, payload: []const u32) void {
        if (payload.len < 1) {
            self.recordInvalidPacket();
            return;
        }
        const event_id = payload[0] & 0x3F;
        const address = self.register_file.peek(regs.RB_SAMPLE_COUNT_ADDR) & ~@as(u32, 3);
        self.register_file.write(regs.VGT_EVENT_INITIATOR, event_id);

        if (address != 0 and self.memory_read_callback != null) {
            const finished = 0xFFFF_FEED;
            const zpass_a = self.readMemory(address + 16);
            const zpass_b = self.readMemory(address + 20);
            const zfail_a = self.readMemory(address + 8);
            const zfail_b = self.readMemory(address + 12);
            const query_finished = (zpass_a == finished and zpass_b == finished) or
                (zfail_a == finished and zfail_b == finished);
            // The structure is little-endian by contract, independent of the
            // PM4 address's endian selector.
            for (0..8) |index| self.writeMemory(address +% @as(u32, @intCast(index * 4)), 0);
            if (query_finished) {
                self.writeMemory(address, self.occlusion_samples);
                self.writeMemory(address + 16, self.occlusion_samples);
                self.occlusion_samples = if (self.occlusion_samples <= 80) 100 else self.occlusion_samples - 1;
            }
        }
        self.emitEvent(.{ .event_write_zpd = .{ .event_id = event_id, .sample_count_address = address } });
    }

    fn executeRegisterToMemory(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const register = payload[0];
        const address = payload[1];
        if (register >= regs.register_count) {
            self.recordInvalidPacket();
            return;
        }
        self.writeMemory(address, self.register_file.peek(@intCast(register)));
    }

    fn executeConditionalExecute(self: *Executor, payload: []const u32) void {
        // COND_EXEC contains a physical predicate address followed by the
        // number of ring dwords to skip when the predicate is false.  The
        // command processor owns the stream, so the skip is handed back to
        // the bounded walker rather than attempting to execute an arbitrary
        // slice from inside this handler.
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        self.conditional_execute_count +%= 1;
        const address = payload[0];
        const execute_dwords = @min(payload[1], 0x0010_0000);
        const predicate = self.readMemory(address) orelse 0;
        if (predicate == 0) {
            self.conditional_skip_count +%= 1;
            self.conditional_skip_dwords = execute_dwords;
        }
    }

    fn executeConditionalWrite(self: *Executor, payload: []const u32) void {
        if (payload.len < 6) {
            self.recordInvalidPacket();
            return;
        }
        const wait_info = payload[0];
        const address = payload[1];
        const reference = payload[2];
        const mask = payload[3];
        const memory = (wait_info & 0x10) != 0;
        var value: ?u32 = null;
        if (memory) {
            if (self.memory_read_callback) |callback| {
                value = callback(self.memory_read_context orelse @ptrCast(@constCast(&self.register_file)), address);
            }
        } else if (address < regs.register_count) {
            value = self.register_file.peek(@intCast(address));
        }
        if (value == null or !matchesWait(value.? & mask, reference, @truncate(wait_info))) return;
        self.conditional_write_count +%= 1;
        const destination = payload[4];
        if ((wait_info & 0x100) != 0) {
            self.writeMemory(destination, payload[5]);
        } else if (destination < regs.register_count) {
            self.register_file.write(@intCast(destination), payload[5]);
        }
    }

    fn executeIndirectBuffer(self: *Executor, payload: []const u32) void {
        if (payload.len < 2) {
            self.recordInvalidPacket();
            return;
        }
        const address = payload[0];
        const size_dwords = payload[1] & 0x000F_FFFF;
        self.indirect_buffer_count +%= 1;
        self.emitEvent(.{ .indirect_buffer = .{ .address = address, .size_dwords = size_dwords } });
        if (self.indirect_buffer_callback) |callback| {
            callback(self.indirect_buffer_context orelse @ptrCast(@constCast(&self.register_file)), address, size_dwords);
        }
    }

    fn writeMemory(self: *Executor, encoded_address: u32, value: u32) void {
        const endian: u2 = @truncate(encoded_address);
        const address = encoded_address & ~@as(u32, 3);
        if (self.memory_write_callback) |callback| {
            if (!callback(self.memory_write_context orelse @ptrCast(@constCast(&self.register_file)), address, value, endian)) {
                self.deferred_memory_count +%= 1;
            }
        } else {
            self.deferred_memory_count +%= 1;
        }
        self.emitEvent(.{ .memory_write = .{ .address = address, .value = value, .endian = endian } });
    }

    fn readMemory(self: *const Executor, address: u32) ?u32 {
        const callback = self.memory_read_callback orelse return null;
        return callback(
            self.memory_read_context orelse @ptrCast(@constCast(&self.register_file)),
            address,
        );
    }

    fn emitEvent(self: *Executor, event: Event) void {
        self.event_count +%= 1;
        if (self.event_callback) |callback| callback(self.callback_context orelse @ptrCast(@constCast(&self.register_file)), event);
    }

    fn fail(self: *Executor, err: Failure) Error {
        self.invalid_packet_count +%= 1;
        self.last_error = err;
        return switch (err) {
            .truncated_packet => error.truncated_packet,
            .invalid_packet => error.invalid_packet,
            .wait_condition_failed => error.wait_condition_failed,
        };
    }

    fn recordInvalidPacket(self: *Executor) void {
        self.invalid_packet_count +%= 1;
        self.last_error = .invalid_packet;
    }
};

fn payloadValue(payload: []const u32, index: usize) u32 {
    return if (index < payload.len) payload[index] else 0;
}

fn constantBankBase(kind: u32) ?u32 {
    return switch (kind) {
        0 => regs.shader_constant_alu_base,
        1 => regs.shader_constant_fetch_base,
        2 => regs.shader_constant_bool_base,
        3 => regs.shader_constant_loop_base,
        4 => regs.shader_constant_register_base,
        else => null,
    };
}

fn matchesWait(value: u32, reference: u32, relation: u3) bool {
    return switch (relation) {
        0 => value < reference,
        1 => value <= reference,
        2 => value == reference,
        3 => value != reference,
        4 => value >= reference,
        5 => value > reference,
        else => true,
    };
}

const MemoryProbe = struct {
    base: u32 = 0x1000,
    bytes: [128]u8 = [_]u8{0} ** 128,

    fn read(context: *anyopaque, address: u32) ?u32 {
        const self: *MemoryProbe = @ptrCast(@alignCast(context));
        const aligned = address & ~@as(u32, 3);
        if (aligned < self.base or aligned - self.base + 4 > self.bytes.len) return null;
        const raw = std.mem.readInt(u32, self.bytes[@intCast(aligned - self.base)..][0..4], .little);
        return switch (@as(u2, @truncate(address))) {
            0 => raw,
            1 => ((raw << 8) & 0xFF00_FF00) | ((raw >> 8) & 0x00FF_00FF),
            2 => @byteSwap(raw),
            3 => (raw >> 16) | (raw << 16),
        };
    }

    fn write(context: *anyopaque, address: u32, value: u32, endian: u2) bool {
        const self: *MemoryProbe = @ptrCast(@alignCast(context));
        if (address < self.base or address - self.base + 4 > self.bytes.len) return false;
        const swapped = switch (endian) {
            0 => value,
            1 => ((value << 8) & 0xFF00_FF00) | ((value >> 8) & 0x00FF_00FF),
            2 => @byteSwap(value),
            3 => (value >> 16) | (value << 16),
        };
        std.mem.writeInt(u32, self.bytes[@intCast(address - self.base)..][0..4], swapped, .little);
        return true;
    }
};

test "PM4 executor applies register packets and extracts a draw" {
    const draw = pm4.packetType3(.draw_indx_2, 3, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .dma,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    };
    var executor: Executor = .{};
    try executor.execute(&.{ draw, initiator.encode(), 0x2000, 3 });
    try std.testing.expectEqual(@as(u64, 1), executor.draw_count);
    try std.testing.expectEqual(@as(u32, 3), executor.last_draw.?.count);
    try std.testing.expectEqual(regs.PrimitiveType.triangle_list, executor.last_draw.?.primitive);
}

test "PM4 type-1 writes both header-selected registers" {
    const header = pm4.packetType1(7, 9).?;
    var executor: Executor = .{};
    try executor.execute(&.{ header, 0x1111, 0x2222 });
    try std.testing.expectEqual(@as(u32, 0x1111), executor.register_file.peek(7));
    try std.testing.expectEqual(@as(u32, 0x2222), executor.register_file.peek(9));
}

test "PM4 predication follows the bin mask and never executes a predicated swap" {
    const set_mask = pm4.packetType3(.set_bin_mask, 2, false).?;
    const set_select = pm4.packetType3(.set_bin_select, 2, false).?;
    const predicated_write = pm4.packetType3(.set_constant2, 2, true).?;
    var executor: Executor = .{};
    try executor.execute(&.{
        set_mask,         0,                             1,
        set_select,       0,                             1,
        predicated_write, regs.shader_constant_alu_base, 0xCAFE,
    });
    try std.testing.expectEqual(@as(u32, 0xCAFE), executor.register_file.peek(regs.shader_constant_alu_base));

    var skipped: Executor = .{};
    try skipped.execute(&.{ predicated_write, 0, 0xBEEF });
    try std.testing.expectEqual(@as(u64, 1), skipped.predicated_skip_count);
    try std.testing.expectEqual(@as(u32, 0), skipped.register_file.peek(regs.shader_constant_alu_base));
}

test "PM4 conditional execute skips the bounded following dword range" {
    const cond = pm4.packetType3(.cond_exec, 2, false).?;
    const write = pm4.packetType3(.set_constant2, 2, false).?;
    var memory = MemoryProbe{};
    var executor: Executor = .{
        .memory_read_context = @ptrCast(&memory),
        .memory_read_callback = MemoryProbe.read,
    };
    try executor.execute(&.{
        cond,  0x1000,                        3,
        write, regs.shader_constant_alu_base, 0xBEEF,
    });
    try std.testing.expectEqual(@as(u64, 1), executor.conditional_execute_count);
    try std.testing.expectEqual(@as(u64, 1), executor.conditional_skip_count);
    try std.testing.expectEqual(@as(u32, 0), executor.register_file.peek(regs.shader_constant_alu_base));
}

test "PM4 MEM_WRITE_CNTR snapshots the command progress counter" {
    const packet = pm4.packetType3(.mem_write_cntr, 1, false).?;
    var memory = MemoryProbe{};
    var executor: Executor = .{
        .memory_write_context = @ptrCast(&memory),
        .memory_write_callback = MemoryProbe.write,
    };
    try executor.execute(&.{ packet, 0x1001 });
    try std.testing.expectEqual(@as(u64, 1), executor.memory_counter_write_count);
    try std.testing.expectEqual(executor.register_file.peek(regs.CP_PROG_COUNTER), MemoryProbe.read(@ptrCast(&memory), 0x1001).?);
}

test "PM4 SET_BIN_BASE_OFFSET records the surface base update" {
    const packet = pm4.packetType3(.set_bin_base_offset, 1, false).?;
    var executor: Executor = .{};
    try executor.execute(&.{ packet, 0x1234_5000 });
    try std.testing.expectEqual(@as(u32, 0x1234_5000), executor.bin_base_offset);
    try std.testing.expectEqual(@as(u64, 1), executor.surface_base_update_count);
}

test "PM4 EVENT_WRITE_SHD commits the guest completion fence" {
    const packet = pm4.packetType3(.event_write_shd, 3, false).?;
    var memory = MemoryProbe{};
    var executor: Executor = .{
        .memory_read_context = @ptrCast(&memory),
        .memory_read_callback = MemoryProbe.read,
        .memory_write_context = @ptrCast(&memory),
        .memory_write_callback = MemoryProbe.write,
    };
    try executor.execute(&.{ packet, 3, 0x1001, 0xCAFE_BABE });
    try std.testing.expectEqual(@as(u32, 0xCAFE_BABE), MemoryProbe.read(@ptrCast(&memory), 0x1001).?);
    try std.testing.expectEqual(@as(u32, 3), executor.register_file.peek(regs.VGT_EVENT_INITIATOR));
}

test "PM4 EVENT_WRITE_EXT writes Xenia's six 16-bit screen extents" {
    const packet = pm4.packetType3(.event_write_ext, 2, false).?;
    var memory = MemoryProbe{};
    var executor: Executor = .{
        .memory_write_context = @ptrCast(&memory),
        .memory_write_callback = MemoryProbe.write,
    };
    try executor.execute(&.{ packet, 7, 0x1001 });
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, memory.bytes[0..2], .little));
    try std.testing.expectEqual(@as(u16, 8), std.mem.readInt(u16, memory.bytes[2..4], .little));
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, memory.bytes[4..6], .little));
    try std.testing.expectEqual(@as(u16, 8), std.mem.readInt(u16, memory.bytes[6..8], .little));
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, memory.bytes[8..10], .little));
    try std.testing.expectEqual(@as(u16, 0x0100), std.mem.readInt(u16, memory.bytes[10..12], .little));
}

test "PM4 EVENT_WRITE_ZPD clears a finished query and writes the sample count" {
    const packet = pm4.packetType3(.event_write_zpd, 1, false).?;
    var memory = MemoryProbe{};
    // Xenia's xe_gpu_depth_sample_counts puts ZFail_A/B at +8/+12.  Keep
    // ZPass_A/B clear here so the test catches an implementation that uses
    // the trailing padding as the completion marker.
    std.mem.writeInt(u32, memory.bytes[0x28..][0..4], 0xFFFF_FEED, .little);
    std.mem.writeInt(u32, memory.bytes[0x2C..][0..4], 0xFFFF_FEED, .little);
    var executor: Executor = .{
        .memory_read_context = @ptrCast(&memory),
        .memory_read_callback = MemoryProbe.read,
        .memory_write_context = @ptrCast(&memory),
        .memory_write_callback = MemoryProbe.write,
    };
    executor.register_file.write(regs.RB_SAMPLE_COUNT_ADDR, 0x1020);
    try executor.execute(&.{ packet, 4 });
    try std.testing.expectEqual(@as(u32, 100), MemoryProbe.read(@ptrCast(&memory), 0x1020).?);
    try std.testing.expectEqual(@as(u32, 100), MemoryProbe.read(@ptrCast(&memory), 0x1030).?);
    try std.testing.expectEqual(@as(u32, 0), MemoryProbe.read(@ptrCast(&memory), 0x1024).?);
    try std.testing.expectEqual(@as(u32, 99), executor.occlusion_samples);
}

test "PM4 SET_CONSTANT addresses each Xenia constant bank by dword index" {
    const packet = pm4.packetType3(.set_constant, 3, false).?;
    var executor: Executor = .{};
    try executor.execute(&.{
        packet,
        (@as(u32, 1) << 16) | 5,
        0x1111,
        0x2222,
    });
    try std.testing.expectEqual(@as(u32, 0x1111), executor.register_file.peek(regs.shader_constant_fetch_base + 5));
    try std.testing.expectEqual(@as(u32, 0x2222), executor.register_file.peek(regs.shader_constant_fetch_base + 6));

    const bool_packet = pm4.packetType3(.set_constant, 2, false).?;
    try executor.execute(&.{ bool_packet, (@as(u32, 2) << 16) | 3, 1 });
    try std.testing.expectEqual(@as(u32, 1), executor.register_file.peek(regs.shader_constant_bool_base + 3));
}

test "PM4 LOAD_ALU_CONSTANT copies guest dwords into the selected bank" {
    const packet = pm4.packetType3(.load_alu_constant, 3, false).?;
    var memory = MemoryProbe{};
    std.mem.writeInt(u32, memory.bytes[0..4], 0xAABB_CCDD, .little);
    std.mem.writeInt(u32, memory.bytes[4..8], 0x1122_3344, .little);
    var executor: Executor = .{
        .memory_read_context = @ptrCast(&memory),
        .memory_read_callback = MemoryProbe.read,
    };
    try executor.execute(&.{ packet, 0x1000, (@as(u32, 1) << 16) | 7, 2 });
    try std.testing.expectEqual(@as(u32, 0xAABB_CCDD), executor.register_file.peek(regs.shader_constant_fetch_base + 7));
    try std.testing.expectEqual(@as(u32, 0x1122_3344), executor.register_file.peek(regs.shader_constant_fetch_base + 8));
    try std.testing.expectEqual(@as(u64, 1), executor.shader_memory_load_count);
    try std.testing.expectEqual(@as(u64, 2), executor.shader_dwords_loaded);
}

test "PM4 VIZ_QUERY updates the event initiator and completion status" {
    const packet = pm4.packetType3(.viz_query, 1, false).?;
    var executor: Executor = .{};
    try executor.execute(&.{ packet, 7 });
    try std.testing.expectEqual(@as(u32, 7), executor.register_file.peek(regs.VGT_EVENT_INITIATOR));
    try executor.execute(&.{ packet, 40 | 0x100 });
    try std.testing.expectEqual(@as(u32, 8), executor.register_file.peek(regs.VGT_EVENT_INITIATOR));
    try std.testing.expectEqual(@as(u32, 1 << 8), executor.register_file.peek(regs.PA_SC_VIZ_QUERY_STATUS_1));
}

test "PM4 DRAW_INDX captures the DMA index buffer fields" {
    const draw = pm4.packetType3(.draw_indx, 4, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .dma,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 6,
    };
    var executor: Executor = .{};
    try executor.execute(&.{ draw, 0, initiator.encode(), 0x1235, 7 | (@as(u32, 3) << 30) });
    try std.testing.expect(executor.last_draw.?.indexed);
    try std.testing.expectEqual(@as(u32, 0x1234), executor.last_draw.?.index_address);
    try std.testing.expectEqual(@as(u32, 7), executor.last_draw.?.index_size_words);
}

test "PM4 draw extraction carries the signed Xenos index offset" {
    const draw = pm4.packetType3(.draw_indx_2, 1, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    };
    var executor: Executor = .{};
    executor.register_file.write(regs.VGT_INDX_OFFSET, 0x00FF_FFF8);
    try executor.execute(&.{ draw, initiator.encode() });
    try std.testing.expectEqual(@as(i32, -8), executor.last_draw.?.index_offset);
}

test "PM4 DRAW_INDX_2 does not reuse a stale DMA buffer for auto-index draws" {
    const draw = pm4.packetType3(.draw_indx_2, 1, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint32,
        .not_end_of_pipe = false,
        .index_count = 3,
    };
    var executor: Executor = .{};
    executor.register_file.write(regs.VGT_DMA_BASE, 0x2000);
    executor.register_file.write(regs.VGT_DMA_SIZE, 99);
    try executor.execute(&.{ draw, initiator.encode() });
    try std.testing.expect(!executor.last_draw.?.indexed);
    try std.testing.expectEqual(@as(u32, 0), executor.last_draw.?.index_address);
    try std.testing.expectEqual(@as(u32, 0), executor.last_draw.?.index_size_words);
}

test "PM4 DRAW_INDX reads DMA fields only for DMA-source draws" {
    const packet = pm4.packetType3(.draw_indx, 2, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .auto_index,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    };
    var executor: Executor = .{};
    executor.register_file.write(regs.VGT_DMA_BASE, 0x2000);
    executor.register_file.write(regs.VGT_DMA_SIZE, 99);
    try executor.execute(&.{ packet, 0, initiator.encode() });
    try std.testing.expectEqual(@as(u64, 1), executor.draw_count);
    try std.testing.expect(!executor.last_draw.?.indexed);
    try std.testing.expectEqual(@as(u32, 0x2000), executor.register_file.peek(regs.VGT_DMA_BASE));
    try std.testing.expectEqual(@as(u32, 99), executor.register_file.peek(regs.VGT_DMA_SIZE));
}

test "PM4 immediate-index draws are recorded as unsupported and not submitted" {
    const packet = pm4.packetType3(.draw_indx_2, 3, false).?;
    const initiator = regs.DrawInitiator{
        .primitive = .triangle_list,
        .source = .immediate,
        .major_mode_explicit = false,
        .index_format = .uint16,
        .not_end_of_pipe = false,
        .index_count = 3,
    };
    var executor: Executor = .{};
    try executor.execute(&.{ packet, initiator.encode(), 0xCAFE, 0xBABE });
    try std.testing.expectEqual(@as(u64, 1), executor.unsupported_immediate_draw_count);
    try std.testing.expectEqual(@as(u64, 0), executor.draw_count);
    try std.testing.expect(executor.last_draw == null);
}

test "PM4 executor refuses a packet whose count walks past the ring span" {
    const header = pm4.packetType3(.nop, 4, false).?;
    var executor: Executor = .{};
    try std.testing.expectError(Error.truncated_packet, executor.execute(&.{ header, 0 }));
    try std.testing.expectEqual(@as(u64, 1), executor.invalid_packet_count);
}

test "PM4 executor recognizes the authentic XE_SWAP message" {
    var packet: [pm4.swap_reservation_dwords]u32 = undefined;
    _ = pm4.encodeSwapSequence(&packet, .{}, .{ .frontbuffer_physical_address = 0x1000, .width = 1280, .height = 720 }, pm4.swap_reservation_dwords).?;
    var executor: Executor = .{};
    try executor.execute(&packet);
    try std.testing.expectEqual(@as(u64, 1), executor.swap_count);
    try std.testing.expectEqual(@as(u32, 1280), executor.last_swap.?.width);
}
