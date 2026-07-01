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
    cleanup_landing_pad: u64 = 0,
};

pub const Handler = struct {
    landing_pad: u64,
    selector: i64,
    frame_index: usize,
    function_start: u64,
    frame_pointer: u64,
    stack_pointer: u64,
    mode: compact_unwind.Mode,
    catch_all: bool,
};

pub const Inspection = struct {
    frames: [MAX_FRAMES]Frame = [_]Frame{Frame{}} ** MAX_FRAMES,
    frame_count: usize = 0,
    metadata_frames: usize = 0,
    handler: ?Handler = null,
    frame_chain_valid: bool = true,
    phase_two_supported: bool = false,
    phase_two_installed: bool = false,
};

pub const Engine = struct {
    const ActivePhaseTwo = struct {
        inspection: Inspection,
        exception_header: u64,
        next_frame: usize,
    };

    compact: ?compact_unwind.Index = null,
    active_phase_two: ?ActivePhaseTwo = null,
    inspections: u64 = 0,
    frames_walked: u64 = 0,
    handlers_found: u64 = 0,
    phase_two_attempts: u64 = 0,
    phase_two_installs: u64 = 0,
    cleanup_installs: u64 = 0,
    resume_calls: u64 = 0,

    pub fn configure(self: *Engine, metadata: anytype) void {
        const section = metadata.sectionNamed("__TEXT", "__unwind_info") orelse return;
        const bytes = metadata.sectionBytes(section) orelse return;
        const image_base = unwindImageBase(metadata);
        self.compact = compact_unwind.Index.init(bytes, section.address, image_base);
        if (self.compact != null) {
            std.debug.print(
                "macho-processor: Itanium unwind engine indexed __unwind_info: address=0x{x} size={d} image_base=0x{x}\n",
                .{ section.address, section.size, image_base },
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
                    if (info.lsda_address != 0) {
                        if (findLandingPad(state, info, instruction -| 1, type_info_address)) |landing| {
                            if (landing.handles_exception and result.handler == null) {
                                result.handler = .{
                                    .landing_pad = landing.address,
                                    .selector = landing.selector,
                                    .frame_index = frame_index,
                                    .function_start = info.function_start,
                                    .frame_pointer = frame_pointer,
                                    .stack_pointer = stack_pointer,
                                    .mode = info.mode,
                                    .catch_all = landing.catch_all,
                                };
                            } else if (!landing.handles_exception) {
                                frame.cleanup_landing_pad = landing.address;
                            }
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

    pub fn installPhaseTwo(
        self: *Engine,
        state: anytype,
        inspection: *Inspection,
        exception_header: u64,
    ) bool {
        self.phase_two_attempts +|= 1;
        if (inspection.handler == null) return false;
        if (exception_header == 0) return false;

        inspection.phase_two_supported = true;
        self.active_phase_two = .{
            .inspection = inspection.*,
            .exception_header = exception_header,
            .next_frame = 0,
        };
        if (!self.installNextPhaseTwoTarget(state)) {
            self.active_phase_two = null;
            inspection.phase_two_supported = false;
            return false;
        }
        inspection.phase_two_installed = true;
        return true;
    }

    pub fn resumePhaseTwo(self: *Engine, state: anytype) bool {
        if (self.active_phase_two == null) return false;
        self.resume_calls +|= 1;
        return self.installNextPhaseTwoTarget(state);
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.inspections == 0 and self.compact == null) return;
        std.debug.print(
            "macho-processor: Itanium unwind summary: metadata={} inspections={d} frames={d} handlers={d} phase_two={d}/{d} cleanups={d} resumes={d}\n",
            .{ self.compact != null, self.inspections, self.frames_walked, self.handlers_found, self.phase_two_installs, self.phase_two_attempts, self.cleanup_installs, self.resume_calls },
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
                    "  unwind[{d}] {s}+0x{x} rbp=0x{x} mode={s} lsda=0x{x} cleanup=0x{x}\n",
                    .{ index, resolved.name, resolved.offset, frame.frame_pointer, @tagName(frame.mode), frame.lsda_address, frame.cleanup_landing_pad },
                );
            } else {
                std.debug.print(
                    "  unwind[{d}] ip=0x{x} rbp=0x{x} mode={s} lsda=0x{x} cleanup=0x{x}\n",
                    .{ index, frame.instruction, frame.frame_pointer, @tagName(frame.mode), frame.lsda_address, frame.cleanup_landing_pad },
                );
            }
        }
        if (inspection.handler) |handler| {
            std.debug.print(
                "macho-processor: Itanium phase-1 handler candidate: frame={d} landing_pad=0x{x} selector={d} catch_all={}\n",
                .{ handler.frame_index, handler.landing_pad, handler.selector, handler.catch_all },
            );
        } else {
            std.debug.print("macho-processor: Itanium phase-1 found no matching catch handler\n", .{});
        }
    }

    fn installNextPhaseTwoTarget(self: *Engine, state: anytype) bool {
        const active = if (self.active_phase_two) |*phase_two| phase_two else return false;
        const handler = active.inspection.handler orelse return false;
        while (active.next_frame < handler.frame_index) {
            const index = active.next_frame;
            active.next_frame += 1;
            const frame = active.inspection.frames[index];
            if (frame.cleanup_landing_pad == 0) continue;
            if (!installContext(state, frame, frame.cleanup_landing_pad, 0, active.exception_header)) return false;
            self.cleanup_installs +|= 1;
            std.debug.print(
                "macho-processor: Itanium phase-2 cleanup installed: frame={d} landing_pad=0x{x} exception=0x{x}\n",
                .{ index, frame.cleanup_landing_pad, active.exception_header },
            );
            return true;
        }

        const handler_frame = active.inspection.frames[handler.frame_index];
        if (!installContext(state, handler_frame, handler.landing_pad, handler.selector, active.exception_header)) return false;
        self.phase_two_installs +|= 1;
        std.debug.print(
            "macho-processor: Itanium phase-2 handler installed: frame={d} landing_pad=0x{x} selector={d} rbp=0x{x} rsp=0x{x} exception=0x{x}\n",
            .{ handler.frame_index, handler.landing_pad, handler.selector, state.regs.rbp, state.regs.rsp, active.exception_header },
        );
        self.active_phase_two = null;
        return true;
    }
};

fn unwindImageBase(metadata: anytype) u64 {
    const text = metadata.sectionNamed("__TEXT", "__text");
    return if (text) |text_section|
        text_section.address -| text_section.file_offset
    else
        metadata.imageBase();
}

const LandingPad = struct {
    address: u64,
    selector: i64,
    catch_all: bool,
    handles_exception: bool,
};

fn findLandingPad(state: anytype, frame: compact_unwind.FrameInfo, instruction: u64, thrown_type: u64) ?LandingPad {
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
        if (landing_offset == 0) return null;
        if (action == 0) {
            return .{
                .address = lp_start + landing_offset,
                .selector = 0,
                .catch_all = false,
                .handles_exception = false,
            };
        }
        if (type_encoding == DW_EH_PE_OMIT) return null;

        var action_position = std.math.add(usize, action_table, @as(usize, @intCast(action - 1))) catch return null;
        var has_cleanup = false;
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
                        return .{
                            .address = lp_start + landing_offset,
                            .selector = type_filter,
                            .catch_all = catch_type == 0,
                            .handles_exception = true,
                        };
                    }
                }
            } else if (type_filter == 0) {
                has_cleanup = true;
            }
            if (next == 0) break;
            const next_position = @as(i64, @intCast(cursor)) + next;
            if (next_position < 0 or next_position >= data.len) return null;
            action_position = @intCast(next_position);
        }
        return if (has_cleanup) .{
            .address = lp_start + landing_offset,
            .selector = 0,
            .catch_all = false,
            .handles_exception = false,
        } else null;
    }
    return null;
}

fn installContext(state: anytype, frame: Frame, landing_pad: u64, selector: i64, exception_header: u64) bool {
    if (frame.mode != .rbp_frame or frame.frame_pointer == 0) return false;
    const prologue = state.guestMemoryConst(frame.function_start, 16) orelse return false;
    const stack_allocation = rbpStackAllocation(prologue) orelse return false;
    const restored_rsp = frame.frame_pointer -| stack_allocation;
    if (restored_rsp == 0 or state.guestMemoryConst(restored_rsp, @max(stack_allocation, 1)) == null) return false;

    state.regs.rbp = frame.frame_pointer;
    state.regs.rsp = restored_rsp;
    state.regs.rax = exception_header;
    state.regs.rdx = @bitCast(selector);
    state.regs.rip = landing_pad;
    return true;
}

fn rbpStackAllocation(prologue: []const u8) ?u64 {
    if (prologue.len < 4 or !std.mem.eql(u8, prologue[0..4], &.{ 0x55, 0x48, 0x89, 0xE5 })) return null;
    if (prologue.len >= 11 and std.mem.eql(u8, prologue[4..7], &.{ 0x48, 0x81, 0xEC })) {
        if (isCalleeSavePush(prologue[11..])) return null;
        return std.mem.readInt(u32, prologue[7..11], .little);
    }
    if (prologue.len >= 8 and std.mem.eql(u8, prologue[4..7], &.{ 0x48, 0x83, 0xEC })) {
        if (isCalleeSavePush(prologue[8..])) return null;
        return prologue[7];
    }
    if (isCalleeSavePush(prologue[4..])) return null;
    return 0;
}

fn isCalleeSavePush(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    return bytes[0] == 0x53 or bytes[0] == 0x56 or bytes[0] == 0x57 or
        (bytes.len >= 2 and bytes[0] == 0x41 and bytes[1] >= 0x54 and bytes[1] <= 0x57);
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

test "phase two accepts canonical rbp stack frames" {
    const wide = [_]u8{ 0x55, 0x48, 0x89, 0xE5, 0x48, 0x81, 0xEC, 0x40, 0x01, 0x00, 0x00 };
    const narrow = [_]u8{ 0x55, 0x48, 0x89, 0xE5, 0x48, 0x83, 0xEC, 0x20 };
    const unsupported = [_]u8{ 0x53, 0x48, 0x83, 0xEC, 0x20 };
    const saved_register = [_]u8{ 0x55, 0x48, 0x89, 0xE5, 0x53, 0x48, 0x83, 0xEC, 0x20 };

    try std.testing.expectEqual(@as(?u64, 0x140), rbpStackAllocation(&wide));
    try std.testing.expectEqual(@as(?u64, 0x20), rbpStackAllocation(&narrow));
    try std.testing.expectEqual(@as(?u64, null), rbpStackAllocation(&unsupported));
    try std.testing.expectEqual(@as(?u64, null), rbpStackAllocation(&saved_register));
}

test "LSDA inspection distinguishes cleanup and typed catch landing pads" {
    const FakeState = struct {
        data: []const u8,

        fn guestMemoryConst(self: @This(), address: u64, count: u64) ?[]const u8 {
            if (address != 0x2000) return null;
            return self.data[0..@min(self.data.len, @as(usize, @intCast(count)))];
        }

        fn read64(_: @This(), _: u64) u64 {
            return 0;
        }
    };
    const frame = compact_unwind.FrameInfo{
        .function_start = 0x1000,
        .function_end = 0x1100,
        .encoding = 0x5100_0000,
        .mode = .rbp_frame,
        .lsda_address = 0x2000,
    };

    const cleanup_lsda = [_]u8{ 0xFF, 0xFF, 0x01, 0x04, 0x00, 0x10, 0x20, 0x00 };
    const cleanup = findLandingPad(FakeState{ .data = &cleanup_lsda }, frame, 0x1005, 0x3000).?;
    try std.testing.expect(!cleanup.handles_exception);
    try std.testing.expectEqual(@as(u64, 0x1020), cleanup.address);

    var catch_lsda = [_]u8{
        0xFF, 0x00, 0x10, 0x01, 0x04, 0x00, 0x10, 0x20, 0x01, 0x01, 0x00,
        0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    const handler = findLandingPad(FakeState{ .data = &catch_lsda }, frame, 0x1005, 0x3000).?;
    try std.testing.expect(handler.handles_exception);
    try std.testing.expectEqual(@as(i64, 1), handler.selector);
    try std.testing.expectEqual(@as(u64, 0x1020), handler.address);
}

test "unwind offsets use the mapped TEXT base instead of PAGEZERO" {
    const FakeMetadata = struct {
        const Section = struct {
            address: u64,
            file_offset: u32,
        };

        fn sectionNamed(_: @This(), segment: []const u8, section: []const u8) ?Section {
            if (std.mem.eql(u8, segment, "__TEXT") and std.mem.eql(u8, section, "__text")) {
                return .{ .address = 0xF2C0, .file_offset = 0xB2C0 };
            }
            return null;
        }

        fn imageBase(_: @This()) u64 {
            return 0;
        }
    };

    try std.testing.expectEqual(@as(u64, 0x4000), unwindImageBase(FakeMetadata{}));
}
