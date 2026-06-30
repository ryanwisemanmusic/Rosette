const std = @import("std");
const compact_unwind = @import("compact_unwind.zig");

const MAX_FRAMES: usize = 48;
const DW_EH_PE_OMIT: u8 = 0xFF;
const DW_EH_PE_PCREL: u8 = 0x10;
const DW_EH_PE_INDIRECT: u8 = 0x80;

pub const Frame = struct {
    instruction: u64 = 0,
    frame_pointer: u64 = 0,
    stack_pointer: u64 = 0,
    function_start: u64 = 0,
    encoding: u32 = 0,
    mode: compact_unwind.Mode = .unknown,
    lsda_address: u64 = 0,
};

pub const Handler = struct {
    landing_pad: u64,
    frame_index: usize,
    function_start: u64,
    frame_pointer: u64,
    stack_pointer: u64,
    catch_all: bool,
};

pub const Inspection = struct {
    frames: [MAX_FRAMES]Frame = [_]Frame{Frame{}} ** MAX_FRAMES,
    frame_count: usize = 0,
    metadata_frames: usize = 0,
    handler: ?Handler = null,
    frame_chain_valid: bool = true,
};

pub const Engine = struct {
    compact: ?compact_unwind.Index = null,
    inspections: u64 = 0,
    frames_walked: u64 = 0,
    handlers_found: u64 = 0,

    pub fn configure(self: *Engine, metadata: anytype) void {
        const section = metadata.sectionNamed("__TEXT", "__unwind_info") orelse return;
        const bytes = metadata.sectionBytes(section) orelse return;
        self.compact = compact_unwind.Index.init(bytes, section.address, metadata.imageBase());
        if (self.compact != null) {
            std.debug.print(
                "macho-processor: Itanium unwind engine indexed __unwind_info: address=0x{x} size={d}\n",
                .{ section.address, section.size },
            );
        }
    }

    pub fn inspectThrow(self: *Engine, state: anytype, type_info_address: u64) Inspection {
        self.inspections +|= 1;
        var result = Inspection{};
        var instruction = state.read64(state.regs.rsp);
        var frame_pointer = state.regs.rbp;
        var stack_pointer = state.regs.rsp + 8;

        while (instruction != 0 and result.frame_count < result.frames.len) {
            const frame_index = result.frame_count;
            var frame = Frame{
                .instruction = instruction,
                .frame_pointer = frame_pointer,
                .stack_pointer = stack_pointer,
            };
            if (self.compact) |*index| {
                if (index.lookup(instruction -| 1)) |info| {
                    frame.function_start = info.function_start;
                    frame.encoding = info.encoding;
                    frame.mode = info.mode;
                    frame.lsda_address = info.lsda_address;
                    result.metadata_frames += 1;
                    if (result.handler == null and info.lsda_address != 0) {
                        if (findHandler(state, info, instruction -| 1, type_info_address)) |landing| {
                            result.handler = .{
                                .landing_pad = landing.address,
                                .frame_index = frame_index,
                                .function_start = info.function_start,
                                .frame_pointer = frame_pointer,
                                .stack_pointer = stack_pointer,
                                .catch_all = landing.catch_all,
                            };
                        }
                    }
                }
            }
            result.frames[frame_index] = frame;
            result.frame_count += 1;

            if (frame_pointer == 0 or state.guestMemoryConst(frame_pointer, 16) == null) break;
            const next_frame = state.read64(frame_pointer);
            const return_address = state.read64(frame_pointer + 8);
            if (next_frame <= frame_pointer or state.guestMemoryConst(next_frame, 16) == null) {
                if (return_address != 0) result.frame_chain_valid = false;
                break;
            }
            stack_pointer = frame_pointer + 16;
            frame_pointer = next_frame;
            instruction = return_address;
        }

        self.frames_walked +|= result.frame_count;
        if (result.handler != null) self.handlers_found +|= 1;
        self.logInspection(state, result);
        return result;
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.inspections == 0 and self.compact == null) return;
        std.debug.print(
            "macho-processor: Itanium unwind summary: metadata={} inspections={d} frames={d} handlers={d}\n",
            .{ self.compact != null, self.inspections, self.frames_walked, self.handlers_found },
        );
    }

    fn logInspection(self: *const Engine, state: anytype, inspection: Inspection) void {
        _ = self;
        std.debug.print(
            "macho-processor: Itanium phase-1 walk: frames={d} metadata_frames={d} frame_chain_valid={}\n",
            .{ inspection.frame_count, inspection.metadata_frames, inspection.frame_chain_valid },
        );
        for (inspection.frames[0..inspection.frame_count], 0..) |frame, index| {
            const symbol = state.metadata.nearestSymbol(frame.instruction -| 1);
            if (symbol) |resolved| {
                std.debug.print(
                    "  unwind[{d}] {s}+0x{x} rbp=0x{x} mode={s} lsda=0x{x}\n",
                    .{ index, resolved.name, resolved.offset, frame.frame_pointer, @tagName(frame.mode), frame.lsda_address },
                );
            } else {
                std.debug.print(
                    "  unwind[{d}] ip=0x{x} rbp=0x{x} mode={s} lsda=0x{x}\n",
                    .{ index, frame.instruction, frame.frame_pointer, @tagName(frame.mode), frame.lsda_address },
                );
            }
        }
        if (inspection.handler) |handler| {
            std.debug.print(
                "macho-processor: Itanium phase-1 handler candidate: frame={d} landing_pad=0x{x} catch_all={} (phase-2 context install deferred)\n",
                .{ handler.frame_index, handler.landing_pad, handler.catch_all },
            );
        } else {
            std.debug.print("macho-processor: Itanium phase-1 found no matching catch handler\n", .{});
        }
    }
};

const LandingPad = struct {
    address: u64,
    catch_all: bool,
};

fn findHandler(state: anytype, frame: compact_unwind.FrameInfo, instruction: u64, thrown_type: u64) ?LandingPad {
    const data = state.guestMemoryConst(frame.lsda_address, 4096) orelse return null;
    var position: usize = 0;
    const lp_encoding = readByte(data, &position) orelse return null;
    var lp_start = frame.function_start;
    if (lp_encoding != DW_EH_PE_OMIT) {
        lp_start = readEncoded(state, data, frame.lsda_address, &position, lp_encoding) orelse return null;
    }

    const type_encoding = readByte(data, &position) orelse return null;
    var type_table: usize = 0;
    if (type_encoding != DW_EH_PE_OMIT) {
        const offset = readUleb(data, &position) orelse return null;
        type_table = std.math.add(usize, position, @intCast(offset)) catch return null;
        if (type_table > data.len) return null;
    }

    const call_site_encoding = readByte(data, &position) orelse return null;
    const call_site_length = readUleb(data, &position) orelse return null;
    const call_site_end = std.math.add(usize, position, @intCast(call_site_length)) catch return null;
    if (call_site_end > data.len) return null;
    const action_table = call_site_end;
    const instruction_offset = instruction -| lp_start;

    while (position < call_site_end) {
        const start = readEncoded(state, data, frame.lsda_address, &position, call_site_encoding) orelse return null;
        const length = readEncoded(state, data, frame.lsda_address, &position, call_site_encoding) orelse return null;
        const landing_offset = readEncoded(state, data, frame.lsda_address, &position, call_site_encoding) orelse return null;
        const action = readUleb(data, &position) orelse return null;
        if (instruction_offset < start or instruction_offset >= start +| length) continue;
        if (landing_offset == 0 or action == 0 or type_encoding == DW_EH_PE_OMIT) return null;

        var action_position = std.math.add(usize, action_table, @as(usize, @intCast(action - 1))) catch return null;
        while (action_position < data.len) {
            var cursor = action_position;
            const type_filter = readSleb(data, &cursor) orelse return null;
            const next = readSleb(data, &cursor) orelse return null;
            if (type_filter > 0) {
                const entry_size = encodedSize(type_encoding) orelse return null;
                const distance = std.math.mul(usize, @intCast(type_filter), entry_size) catch return null;
                if (distance <= type_table) {
                    var type_position = type_table - distance;
                    var catch_type = readEncoded(state, data, frame.lsda_address, &type_position, type_encoding) orelse return null;
                    if ((type_encoding & DW_EH_PE_INDIRECT) != 0 and catch_type != 0) catch_type = state.read64(catch_type);
                    if (catch_type == 0 or catch_type == thrown_type) {
                        return .{ .address = lp_start + landing_offset, .catch_all = catch_type == 0 };
                    }
                }
            }
            if (next == 0) break;
            const next_position = @as(i64, @intCast(cursor)) + next;
            if (next_position < 0 or next_position >= data.len) return null;
            action_position = @intCast(next_position);
        }
        return null;
    }
    return null;
}

fn readEncoded(state: anytype, data: []const u8, base_address: u64, position: *usize, encoding: u8) ?u64 {
    if (encoding == DW_EH_PE_OMIT) return null;
    const start = position.*;
    const format = encoding & 0x0F;
    var value: u64 = switch (format) {
        0x00 => readFixed(data, position, 8, false) orelse return null,
        0x01 => readUleb(data, position) orelse return null,
        0x02 => readFixed(data, position, 2, false) orelse return null,
        0x03 => readFixed(data, position, 4, false) orelse return null,
        0x04 => readFixed(data, position, 8, false) orelse return null,
        0x09 => @bitCast(readSleb(data, position) orelse return null),
        0x0A => readFixed(data, position, 2, true) orelse return null,
        0x0B => readFixed(data, position, 4, true) orelse return null,
        0x0C => readFixed(data, position, 8, true) orelse return null,
        else => return null,
    };
    if ((encoding & 0x70) == DW_EH_PE_PCREL) value +%= base_address + start;
    _ = state;
    return value;
}

fn encodedSize(encoding: u8) ?usize {
    return switch (encoding & 0x0F) {
        0x00, 0x04, 0x0C => 8,
        0x02, 0x0A => 2,
        0x03, 0x0B => 4,
        else => null,
    };
}

fn readByte(data: []const u8, position: *usize) ?u8 {
    if (position.* >= data.len) return null;
    defer position.* += 1;
    return data[position.*];
}

fn readFixed(data: []const u8, position: *usize, size: usize, signed: bool) ?u64 {
    if (position.* + size > data.len) return null;
    const bytes = data[position.* .. position.* + size];
    position.* += size;
    return switch (size) {
        2 => if (signed) @bitCast(@as(i64, std.mem.readInt(i16, bytes[0..2], .little))) else std.mem.readInt(u16, bytes[0..2], .little),
        4 => if (signed) @bitCast(@as(i64, std.mem.readInt(i32, bytes[0..4], .little))) else std.mem.readInt(u32, bytes[0..4], .little),
        8 => if (signed) @bitCast(std.mem.readInt(i64, bytes[0..8], .little)) else std.mem.readInt(u64, bytes[0..8], .little),
        else => null,
    };
}

fn readUleb(data: []const u8, position: *usize) ?u64 {
    var value: u64 = 0;
    var shift: u6 = 0;
    while (position.* < data.len) {
        const byte = data[position.*];
        position.* += 1;
        value |= @as(u64, byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) return value;
        if (shift >= 63) return null;
        shift += 7;
    }
    return null;
}

fn readSleb(data: []const u8, position: *usize) ?i64 {
    var value: u64 = 0;
    var shift: u7 = 0;
    var byte: u8 = 0;
    while (position.* < data.len and shift < 64) {
        byte = data[position.*];
        position.* += 1;
        value |= @as(u64, byte & 0x7F) << @intCast(shift);
        shift += 7;
        if ((byte & 0x80) == 0) break;
    }
    if ((byte & 0x80) != 0) return null;
    if (shift < 64 and (byte & 0x40) != 0) value |= @as(u64, std.math.maxInt(u64)) << @as(u6, @intCast(shift));
    return @bitCast(value);
}
