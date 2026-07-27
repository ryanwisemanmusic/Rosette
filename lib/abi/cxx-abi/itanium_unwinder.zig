const std = @import("std");
const compact_unwind = @import("compact_unwind.zig");
const itanium_dynamic_cast = @import("itanium_dynamic_cast.zig");
const machoCapturePrint = @import("event_log").machoCapturePrint;

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
    cleanup_frames: usize = 0,
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
    phase_two_checkpoint: ?ActivePhaseTwo = null,
    verbose: bool = false,
    inspections: u64 = 0,
    frames_walked: u64 = 0,
    handlers_found: u64 = 0,
    phase_two_attempts: u64 = 0,
    phase_two_installs: u64 = 0,
    cleanup_installs: u64 = 0,
    resume_calls: u64 = 0,
    orphan_resume_attempts: u64 = 0,
    orphan_resume_recoveries: u64 = 0,
    completed_catches: u64 = 0,

    pub fn configure(self: *Engine, metadata: anytype) void {
        const section = metadata.sectionNamed("__TEXT", "__unwind_info") orelse return;
        const bytes = metadata.sectionBytes(section) orelse return;
        const image_base = unwindImageBase(metadata);
        self.compact = compact_unwind.Index.init(bytes, section.address, image_base);
        if (self.compact != null) {
            machoCapturePrint(
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
                    if (self.verbose) {
                        const fsym = state.metadata.nearestSymbol(info.function_start);
                        const fsym_str = if (fsym) |s| s.name else "???";
                        machoCapturePrint(
                            "macho-processor:   frame[{d}] compact_unwind hit: func={s}+0x{x} mode={s} lsda=0x{x}\n",
                            .{ frame_index, fsym_str, info.function_start, @tagName(info.mode), info.lsda_address },
                        );
                    }
                    if (info.lsda_address != 0) {
                        if (findLandingPad(self, state, info, instruction -| 1, type_info_address)) |landing| {
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
                                result.cleanup_frames += 1;
                            }
                        } else if (self.verbose) {
                            machoCapturePrint(
                                "macho-processor:   frame[{d}] compact_unwind MISS for ip=0x{x}\n",
                                .{ frame_index, instruction -| 1 },
                            );
                        }
                    }
                }
            }
            result.frames[frame_index] = frame;
            result.frame_count += 1;

            var next_instruction: u64 = 0;
            var next_fp: u64 = 0;
            var next_sp: u64 = 0;

            if (frame_pointer != 0 and state.guestMemoryConst(frame_pointer, 16) != null) {
                const next_frame = state.read64(frame_pointer);
                const return_address = state.read64(frame_pointer + 8);
                if (next_frame > frame_pointer and state.guestMemoryConst(next_frame, 16) != null) {
                    next_fp = next_frame;
                    next_instruction = return_address;
                    next_sp = frame_pointer + 16;
                    if (self.verbose) {
                        const ret_sym = state.metadata.nearestSymbol(return_address);
                        const ret_str = if (ret_sym) |s| s.name else "???";
                        machoCapturePrint(
                            "macho-processor:   frame[{d}] rbp_chain ok: saved_rbp=0x{x} ret=0x{x} ({s}) next_sp=0x{x}\n",
                            .{ frame_index, next_frame, return_address, ret_str, next_sp },
                        );
                    }
                } else if (next_frame == 0) {
                    // Null saved-rbp signals the outermost frame
                    // (pthread start). Terminate the walk here.
                    if (self.verbose) {
                        machoCapturePrint(
                            "macho-processor:   frame[{d}] rbp_chain TERMINATED: saved_rbp=0 (top of stack) ret=0x{x}\n",
                            .{ frame_index, return_address },
                        );
                    }
                } else if (return_address != 0) {
                    result.frame_chain_valid = false;
                    next_instruction = return_address;
                    next_fp = next_frame;
                    next_sp = frame_pointer + 16;
                    if (self.verbose) {
                        machoCapturePrint(
                            "macho-processor:   frame[{d}] rbp_chain BROKEN: saved_rbp=0x{x} (valid={}) ret=0x{x} continuing via return address\n",
                            .{ frame_index, next_frame, next_frame > frame_pointer and state.guestMemoryConst(next_frame, 16) != null, return_address },
                        );
                    }
                }
            } else if (frame_pointer != 0) {
                result.frame_chain_valid = false;
                if (self.verbose) {
                    machoCapturePrint(
                        "macho-processor:   frame[{d}] rbp=0x{x} memory UNREADABLE, frame chain terminated\n",
                        .{ frame_index, frame_pointer },
                    );
                }
            } else {
                if (self.verbose) {
                    machoCapturePrint(
                        "macho-processor:   frame[{d}] rbp=0x0, frame chain terminated\n",
                        .{frame_index},
                    );
                }
            }

            instruction = next_instruction;
            frame_pointer = next_fp;
            stack_pointer = next_sp;
        }

        self.frames_walked +|= result.frame_count;
        if (result.handler != null) self.handlers_found +|= 1;
        self.logInspection(state, result, type_info_address);
        return result;
    }

    pub fn installPhaseTwo(
        self: *Engine,
        state: anytype,
        inspection: *Inspection,
        exception_header: u64,
    ) bool {
        self.phase_two_attempts +|= 1;
        if (exception_header == 0) return false;
        if (inspection.handler == null and inspection.cleanup_frames == 0) return false;

        inspection.phase_two_supported = true;
        self.active_phase_two = .{
            .inspection = inspection.*,
            .exception_header = exception_header,
            .next_frame = 0,
        };
        self.phase_two_checkpoint = self.active_phase_two;
        if (!self.installNextPhaseTwoTarget(state)) {
            self.active_phase_two = null;
            inspection.phase_two_supported = false;
            return false;
        }
        inspection.phase_two_installed = true;
        return true;
    }

    pub fn resumePhaseTwo(self: *Engine, state: anytype) bool {
        if (self.active_phase_two == null) {
            const checkpoint = self.phase_two_checkpoint orelse return false;
            if (checkpoint.inspection.handler) |handler| {
                // A cursor beyond the handler means phase two completed normally;
                // reinstalling that handler would duplicate catch side effects.
                if (checkpoint.next_frame > handler.frame_index) return false;
            } else if (checkpoint.next_frame >= checkpoint.inspection.frame_count) {
                return false;
            }
            self.active_phase_two = checkpoint;
            machoCapturePrint(
                "macho-processor: Itanium phase-2 transaction restored from checkpoint: next_frame={d} exception=0x{x}\n",
                .{ checkpoint.next_frame, checkpoint.exception_header },
            );
        }
        self.resume_calls +|= 1;
        return self.installNextPhaseTwoTarget(state);
    }

    /// True after every verified cleanup pad has run but no LSDA catch was
    /// present. Continuing guest execution at that point would fabricate an
    /// exception destination, so the caller must report an unhandled throw.
    pub fn exhaustedWithoutHandler(self: *const Engine) bool {
        const checkpoint = self.phase_two_checkpoint orelse return false;
        return checkpoint.inspection.handler == null and checkpoint.next_frame >= checkpoint.inspection.frame_count;
    }

    pub fn recordOrphanResume(self: *Engine, recovered: bool) void {
        self.orphan_resume_attempts +|= 1;
        if (recovered) self.orphan_resume_recoveries +|= 1;
    }

    /// Commits the successful end of an Itanium catch. Checkpoints exist to
    /// survive cleanup-to-`_Unwind_Resume` transitions, but retaining one past
    /// `__cxa_end_catch` lets an unrelated later resume resurrect stale stack
    /// frames and the wrong exception header.
    pub fn completeCatch(self: *Engine) bool {
        const had_transaction = self.active_phase_two != null or self.phase_two_checkpoint != null;
        self.active_phase_two = null;
        self.phase_two_checkpoint = null;
        if (had_transaction) self.completed_catches +|= 1;
        return had_transaction;
    }

    pub fn logSummary(self: *const Engine) void {
        if (self.inspections == 0 and self.compact == null) return;
        machoCapturePrint(
            "macho-processor: Itanium unwind summary: metadata={} inspections={d} frames={d} handlers={d} phase_two={d}/{d} completed_catches={d} cleanups={d} resumes={d} orphan_resume_recovered={d}/{d}\n",
            .{ self.compact != null, self.inspections, self.frames_walked, self.handlers_found, self.phase_two_installs, self.phase_two_attempts, self.completed_catches, self.cleanup_installs, self.resume_calls, self.orphan_resume_recoveries, self.orphan_resume_attempts },
        );
    }

    fn logInspection(self: *const Engine, state: anytype, inspection: Inspection, type_info_address: u64) void {
        machoCapturePrint(
            "macho-processor: Itanium phase-1 walk: frames={d} metadata_frames={d} cleanup_frames={d} frame_chain_valid={}\n",
            .{ inspection.frame_count, inspection.metadata_frames, inspection.cleanup_frames, inspection.frame_chain_valid },
        );
        for (inspection.frames[0..inspection.frame_count], 0..) |frame, index| {
            const symbol = state.metadata.nearestSymbol(frame.instruction -| 1);
            if (symbol) |resolved| {
                machoCapturePrint(
                    "  unwind[{d}] {s}+0x{x} rbp=0x{x} sp=0x{x} mode={s} lsda=0x{x} cleanup=0x{x}\n",
                    .{ index, resolved.name, resolved.offset, frame.frame_pointer, frame.stack_pointer, @tagName(frame.mode), frame.lsda_address, frame.cleanup_landing_pad },
                );
            } else {
                machoCapturePrint(
                    "  unwind[{d}] ip=0x{x} rbp=0x{x} sp=0x{x} mode={s} lsda=0x{x} cleanup=0x{x}\n",
                    .{ index, frame.instruction, frame.frame_pointer, frame.stack_pointer, @tagName(frame.mode), frame.lsda_address, frame.cleanup_landing_pad },
                );
            }
        }
        if (inspection.handler) |handler| {
            machoCapturePrint(
                "macho-processor: Itanium phase-1 handler candidate: frame={d} landing_pad=0x{x} selector={d} catch_all={}\n",
                .{ handler.frame_index, handler.landing_pad, handler.selector, handler.catch_all },
            );
        } else {
            if (inspection.cleanup_frames != 0) {
                machoCapturePrint("macho-processor: Itanium phase-1 found no matching catch handler; phase two will run {d} verified cleanup landing pad(s), then stop as unhandled:\n", .{inspection.cleanup_frames});
            } else {
                machoCapturePrint("macho-processor: Itanium phase-1 found no matching catch handler or cleanup landing pad:\n", .{});
            }
            machoCapturePrint("macho-processor: dumping LSDA details for all frames with non-zero LSDAs:\n", .{});
            if (self.compact) |*compact_index| {
                for (inspection.frames[0..inspection.frame_count]) |frame| {
                    if (frame.lsda_address == 0) continue;
                    if (compact_index.lookup(frame.instruction -| 1)) |info| {
                        logLsdaCallSitesForFrame(state, info, frame.instruction -| 1, type_info_address);
                    }
                }
            }
        }
    }

    fn installNextPhaseTwoTarget(self: *Engine, state: anytype) bool {
        const active = if (self.active_phase_two) |*phase_two| phase_two else return false;
        const final_frame = if (active.inspection.handler) |handler| handler.frame_index else active.inspection.frame_count;
        while (active.next_frame < final_frame) {
            const index = active.next_frame;
            active.next_frame += 1;
            self.phase_two_checkpoint = active.*;
            const frame = active.inspection.frames[index];
            if (frame.cleanup_landing_pad == 0) continue;
            if (!installContext(state, frame, frame.cleanup_landing_pad, 0, active.exception_header)) return false;
            self.cleanup_installs +|= 1;
            machoCapturePrint(
                "macho-processor: Itanium phase-2 cleanup installed: frame={d} landing_pad=0x{x} exception=0x{x}\n",
                .{ index, frame.cleanup_landing_pad, active.exception_header },
            );
            return true;
        }

        const handler = active.inspection.handler orelse {
            active.next_frame = active.inspection.frame_count;
            self.phase_two_checkpoint = active.*;
            self.active_phase_two = null;
            machoCapturePrint(
                "macho-processor: Itanium phase-2 cleanups exhausted without a matching catch; exception remains unhandled\n",
                .{},
            );
            return false;
        };

        const handler_frame = active.inspection.frames[handler.frame_index];
        if (!installContext(state, handler_frame, handler.landing_pad, handler.selector, active.exception_header)) return false;
        active.next_frame = handler.frame_index + 1;
        self.phase_two_checkpoint = active.*;
        self.phase_two_installs +|= 1;
        machoCapturePrint(
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

fn findLandingPad(engine: *const Engine, state: anytype, frame: compact_unwind.FrameInfo, instruction: u64, thrown_type: u64) ?LandingPad {
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

    if (engine.verbose) {
        logLsdaCallSites(state, data, frame, lp_start, lp_encoding, type_encoding, type_table, call_site_encoding, call_site_end, position, instruction_offset, thrown_type);
    }

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
                    // A typed C++ catch accepts an unambiguous public base of
                    // the thrown dynamic type (for example, std::exception
                    // catching a toml::parse_error), not only an exact RTTI
                    // pointer match.
                    if (catch_type == 0 or itanium_dynamic_cast.isCatchCompatible(state, thrown_type, catch_type)) {
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

fn logLsdaCallSitesForFrame(
    state: anytype,
    frame: compact_unwind.FrameInfo,
    instruction: u64,
    thrown_type: u64,
) void {
    const data = state.guestMemoryConst(frame.lsda_address, 4096) orelse {
        machoCapturePrint("macho-processor:   [LSDA] lsda=0x{x} UNREADABLE\n", .{frame.lsda_address});
        return;
    };
    var position: usize = 0;
    const lp_encoding = readByte(data, &position) orelse return;
    var lp_start = frame.function_start;
    if (lp_encoding != DW_EH_PE_OMIT) {
        lp_start = readEncoded(state, data, frame.lsda_address, &position, lp_encoding) orelse return;
    }
    const type_encoding = readByte(data, &position) orelse return;
    var type_table: usize = 0;
    if (type_encoding != DW_EH_PE_OMIT) {
        const offset = readUleb(data, &position) orelse return;
        type_table = std.math.add(usize, position, @intCast(offset)) catch return;
        if (type_table > data.len) return;
    }
    const call_site_encoding = readByte(data, &position) orelse return;
    const call_site_length = readUleb(data, &position) orelse return;
    const call_site_end = std.math.add(usize, position, @intCast(call_site_length)) catch return;
    if (call_site_end > data.len) return;
    const instruction_offset = instruction -| lp_start;

    const symbol = state.metadata.nearestSymbol(frame.function_start);
    const func_name = if (symbol) |s| s.name else "<unknown>";
    machoCapturePrint(
        "macho-processor:   [LSDA] func={s} lsda=0x{x} lp_start=0x{x} ip_offset=0x{x} type_enc=0x{x} cs_enc=0x{x}\n",
        .{ func_name, frame.lsda_address, lp_start, instruction_offset, type_encoding, call_site_encoding },
    );

    var pos = position;
    var cs_index: usize = 0;
    while (pos < call_site_end) {
        const cs_start = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_length = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_landing = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_action = readUleb(data, &pos) orelse return;
        const matches = instruction_offset >= cs_start and instruction_offset < cs_start +| cs_length;
        machoCapturePrint(
            "macho-processor:   [LSDA] call-site[{d}] range=[0x{x},0x{x}) landing=0x{x} action={d} ip_in_range={}\n",
            .{ cs_index, cs_start, cs_start +| cs_length, cs_landing, cs_action, matches },
        );
        if (cs_action != 0 and type_encoding != DW_EH_PE_OMIT) {
            var action_pos = std.math.add(usize, call_site_end, @as(usize, @intCast(cs_action - 1))) catch return;
            while (action_pos < data.len) {
                var cursor = action_pos;
                const tf = readSleb(data, &cursor) orelse break;
                const nxt = readSleb(data, &cursor) orelse break;
                if (tf > 0) {
                    const entry_size = encodedSize(type_encoding) orelse break;
                    const dist = std.math.mul(usize, @intCast(tf), entry_size) catch break;
                    if (dist <= type_table) {
                        var tp = type_table - dist;
                        var ct = readEncoded(state, data, frame.lsda_address, &tp, type_encoding) orelse break;
                        if ((type_encoding & DW_EH_PE_INDIRECT) != 0 and ct != 0) ct = state.read64(ct);
                        const catch_name = if (ct != 0) (state.guestCString(state.read64(ct +| 8), 256) orelse "<unreadable>") else "<catch_all>";
                        const thrown_name = if (thrown_type != 0) (state.guestCString(state.read64(thrown_type +| 8), 256) orelse "<unreadable>") else "<none>";
                        const compatible = ct == 0 or itanium_dynamic_cast.isCatchCompatible(state, thrown_type, ct);
                        machoCapturePrint(
                            "macho-processor:   [LSDA]   catch type_filter={d} catch_type=0x{x} ({s}) thrown=0x{x} ({s}) compatible={}\n",
                            .{ tf, ct, catch_name, thrown_type, thrown_name, compatible },
                        );
                    }
                } else if (tf == 0) {
                    machoCapturePrint("macho-processor:   [LSDA]   cleanup type_filter=0\n", .{});
                }
                if (nxt == 0) break;
                const next_position = @as(i64, @intCast(cursor)) + nxt;
                if (next_position < 0 or next_position >= data.len) return;
                action_pos = @intCast(next_position);
            }
        }
        cs_index +|= 1;
    }
}

fn logLsdaCallSites(
    state: anytype,
    data: []const u8,
    frame: compact_unwind.FrameInfo,
    lp_start: u64,
    lp_encoding: u8,
    type_encoding: u8,
    type_table: usize,
    call_site_encoding: u8,
    call_site_end: usize,
    initial_position: usize,
    instruction_offset: u64,
    thrown_type: u64,
) void {
    const symbol = state.metadata.nearestSymbol(frame.function_start);
    const func_name = if (symbol) |s| s.name else "<unknown>";
    machoCapturePrint(
        "macho-processor:   [LSDA] func={s} lp_start=0x{x} lp_enc=0x{x} type_enc=0x{x} type_table=0x{x} cs_enc=0x{x} cs_end=0x{x} ip_offset=0x{x}\n",
        .{ func_name, lp_start, lp_encoding, type_encoding, type_table, call_site_encoding, call_site_end, instruction_offset },
    );

    var pos = initial_position;
    var cs_index: usize = 0;
    while (pos < call_site_end) {
        const cs_start = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_length = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_landing = readEncoded(state, data, frame.lsda_address, &pos, call_site_encoding) orelse return;
        const cs_action = readUleb(data, &pos) orelse return;
        const matches = instruction_offset >= cs_start and instruction_offset < cs_start +| cs_length;
        machoCapturePrint(
            "macho-processor:   [LSDA] call-site[{d}] range=[0x{x},0x{x}) landing=0x{x} action={d} match={}\n",
            .{ cs_index, cs_start, cs_start +| cs_length, cs_landing, cs_action, matches },
        );
        if (cs_action != 0 and type_encoding != DW_EH_PE_OMIT) {
            var action_pos = std.math.add(usize, call_site_end, @as(usize, @intCast(cs_action - 1))) catch return;
            while (action_pos < data.len) {
                var cursor = action_pos;
                const type_filter = readSleb(data, &cursor) orelse break;
                const next = readSleb(data, &cursor) orelse break;
                if (type_filter > 0) {
                    const entry_size = encodedSize(type_encoding) orelse break;
                    const dist = std.math.mul(usize, @intCast(type_filter), entry_size) catch break;
                    if (dist <= type_table) {
                        var tp = type_table - dist;
                        var ct = readEncoded(state, data, frame.lsda_address, &tp, type_encoding) orelse break;
                        if ((type_encoding & DW_EH_PE_INDIRECT) != 0 and ct != 0) ct = state.read64(ct);
                        const catch_name = if (ct != 0) (state.guestCString(state.read64(ct +| 8), 256) orelse "<unknown>") else "<catch_all>";
                        const thrown_name = state.guestCString(state.read64(thrown_type +| 8), 256) orelse "<unknown>";
                        machoCapturePrint(
                            "macho-processor:   [LSDA]   type-filter={d} catch_type=0x{x} ({s}) thrown_type=0x{x} ({s})\n",
                            .{ type_filter, ct, catch_name, thrown_type, thrown_name },
                        );
                    }
                } else if (type_filter == 0) {
                    machoCapturePrint("macho-processor:   [LSDA]   type-filter=0 (cleanup)\n", .{});
                }
                if (next == 0) break;
                const next_position = @as(i64, @intCast(cursor)) + next;
                if (next_position < 0 or next_position >= data.len) return;
                action_pos = @intCast(next_position);
            }
        }
        cs_index +|= 1;
    }
}

fn installContext(state: anytype, frame: Frame, landing_pad: u64, selector: i64, exception_header: u64) bool {
    const restored_rbp = frame.frame_pointer;
    const restored_rsp = frame.stack_pointer;

    switch (frame.mode) {
        .rbp_frame => {
            if (frame.frame_pointer == 0) return false;
            if (!restoreRbpFrameRegisters(state, frame)) return false;
        },
        // Frameless compact-unwind records: the phase-one walk already
        // computed the correct call-site SP/FP. Accept all modes so that
        // landing pads are installable even when we cannot decode the
        // register permutation — wrong callee-save values are preferable
        // to an unhandled exception.
        .stack_immediate, .stack_indirect, .dwarf => {},
        .unknown => return false,
    }
    // The phase-one walk records the caller RSP at every frame boundary:
    // rsp+8 for the throw frame and child_rbp+16 for each parent. That is the
    // exact call-site stack context required by the landing pad and remains
    // correct with dynamic stack allocation and callee-save pushes. Inferring
    // it from a few prologue bytes loses those cases.
    if (restored_rsp == 0 or state.guestMemoryConst(restored_rsp, 1) == null) return false;

    state.regs.rbp = restored_rbp;
    state.regs.rsp = restored_rsp;
    state.regs.rax = exception_header;
    state.regs.rdx = @bitCast(selector);
    state.regs.rip = landing_pad;
    return true;
}

fn restoreRbpFrameRegisters(state: anytype, frame: Frame) bool {
    const saved_count: u64 = (frame.encoding >> 16) & 0xFF;
    var register_bits = frame.encoding & 0x7FFF;
    if (register_bits == 0) return true;
    if (saved_count == 0 or saved_count > 5) return false;
    const byte_distance = std.math.mul(u64, saved_count, 8) catch return false;
    if (byte_distance > frame.frame_pointer) return false;
    const base = frame.frame_pointer - byte_distance;

    for (0..5) |slot| {
        const register_code: u3 = @truncate(register_bits);
        register_bits >>= 3;
        if (register_code == 0) continue;
        if (slot >= saved_count) return false;
        const address = base + @as(u64, @intCast(slot)) * 8;
        if (state.guestMemoryConst(address, 8) == null) return false;
        const value = state.read64(address);
        switch (register_code) {
            1 => state.regs.rbx = value,
            2 => state.regs.r12 = value,
            3 => state.regs.r13 = value,
            4 => state.regs.r14 = value,
            5 => state.regs.r15 = value,
            else => return false,
        }
    }
    return register_bits == 0;
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
    // A zero encoded pointer is the ABI null pointer even when an application
    // such as pcrel is present. Applying the base first turns a catch-all RTTI
    // entry into an address inside the LSDA and then INDIRECT dereferences
    // unrelated exception-table bytes as a fake type_info pointer.
    if (value == 0) return 0;
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

test "PC-relative encoded null remains a catch-all type pointer" {
    const FakeState = struct {};
    const bytes = [_]u8{ 0, 0, 0, 0 };
    var position: usize = 0;
    try std.testing.expectEqual(@as(?u64, 0), readEncoded(FakeState{}, &bytes, 0x13e7db8, &position, 0x9b));
    try std.testing.expectEqual(@as(usize, 4), position);
}

test "phase two installs the frame-walk call-site stack context" {
    const FakeState = struct {
        const Registers = struct {
            rbp: u64 = 0,
            rsp: u64 = 0,
            rax: u64 = 0,
            rdx: u64 = 0,
            rip: u64 = 0,
            rbx: u64 = 0,
            r12: u64 = 0,
            r13: u64 = 0,
            r14: u64 = 0,
            r15: u64 = 0,
        };
        regs: Registers = .{},
        memory: [32]u8 = [_]u8{0} ** 32,

        fn guestMemoryConst(self: *@This(), address: u64, count: u64) ?[]const u8 {
            if (address < 0x8000 or address + count > 0x8000 + self.memory.len) return null;
            const offset: usize = @intCast(address - 0x8000);
            return self.memory[offset..][0..@intCast(count)];
        }

        fn read64(self: *@This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };
    var state = FakeState{};
    std.mem.writeInt(u64, state.memory[8..16], 0xBBBB, .little);
    std.mem.writeInt(u64, state.memory[16..24], 0xEEEE, .little);
    const frame = Frame{
        .frame_pointer = 0x8018,
        .stack_pointer = 0x8008,
        .mode = .rbp_frame,
        // Two saved slots: RBX at rbp-16 and R14 at rbp-8.
        .encoding = 0x0102_0021,
    };
    try std.testing.expect(installContext(&state, frame, 0x1234, 1, 0x4000));
    try std.testing.expectEqual(@as(u64, 0x8018), state.regs.rbp);
    try std.testing.expectEqual(@as(u64, 0x8008), state.regs.rsp);
    try std.testing.expectEqual(@as(u64, 0x4000), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 1), state.regs.rdx);
    try std.testing.expectEqual(@as(u64, 0x1234), state.regs.rip);
    try std.testing.expectEqual(@as(u64, 0xBBBB), state.regs.rbx);
    try std.testing.expectEqual(@as(u64, 0xEEEE), state.regs.r14);
}

test "phase two resumes from retained cleanup checkpoint" {
    const FakeState = struct {
        const Registers = struct {
            rbp: u64 = 0,
            rsp: u64 = 0,
            rax: u64 = 0,
            rdx: u64 = 0,
            rip: u64 = 0,
            rbx: u64 = 0,
            r12: u64 = 0,
            r13: u64 = 0,
            r14: u64 = 0,
            r15: u64 = 0,
        };
        regs: Registers = .{},
        memory: [64]u8 = [_]u8{0} ** 64,

        fn guestMemoryConst(self: *@This(), address: u64, count: u64) ?[]const u8 {
            if (address < 0x8000 or address + count > 0x8000 + self.memory.len) return null;
            const offset: usize = @intCast(address - 0x8000);
            return self.memory[offset..][0..@intCast(count)];
        }

        fn read64(self: *@This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };

    var inspection = Inspection{};
    inspection.frame_count = 2;
    inspection.frames[0] = .{ .frame_pointer = 0x8010, .stack_pointer = 0x8008, .mode = .rbp_frame, .cleanup_landing_pad = 0x1111 };
    inspection.frames[1] = .{ .frame_pointer = 0x8020, .stack_pointer = 0x8018, .mode = .rbp_frame };
    inspection.handler = .{
        .landing_pad = 0x2222,
        .selector = 1,
        .frame_index = 1,
        .function_start = 0x2000,
        .frame_pointer = 0x8020,
        .stack_pointer = 0x8018,
        .mode = .rbp_frame,
        .catch_all = false,
    };

    var state = FakeState{};
    var engine = Engine{};
    try std.testing.expect(engine.installPhaseTwo(&state, &inspection, 0x4000));
    try std.testing.expectEqual(@as(u64, 0x1111), state.regs.rip);
    engine.active_phase_two = null; // Model an import-boundary state loss.
    try std.testing.expect(engine.resumePhaseTwo(&state));
    try std.testing.expectEqual(@as(u64, 0x2222), state.regs.rip);
    try std.testing.expectEqual(@as(u64, 0x4000), state.regs.rax);
    try std.testing.expectEqual(@as(u64, 1), state.regs.rdx);
    try std.testing.expect(engine.completeCatch());
    try std.testing.expect(!engine.resumePhaseTwo(&state));
    try std.testing.expectEqual(@as(u64, 1), engine.completed_catches);
}

test "phase two runs verified cleanups before reporting an unhandled exception" {
    const FakeState = struct {
        const Registers = struct {
            rbp: u64 = 0,
            rsp: u64 = 0,
            rax: u64 = 0,
            rdx: u64 = 0,
            rip: u64 = 0,
            rbx: u64 = 0,
            r12: u64 = 0,
            r13: u64 = 0,
            r14: u64 = 0,
            r15: u64 = 0,
        };
        regs: Registers = .{},
        memory: [32]u8 = [_]u8{0} ** 32,

        fn guestMemoryConst(self: *@This(), address: u64, count: u64) ?[]const u8 {
            if (address < 0x8000 or address + count > 0x8000 + self.memory.len) return null;
            const offset: usize = @intCast(address - 0x8000);
            return self.memory[offset..][0..@intCast(count)];
        }

        fn read64(self: *@This(), address: u64) u64 {
            const bytes = self.guestMemoryConst(address, 8) orelse return 0;
            return std.mem.readInt(u64, bytes[0..8], .little);
        }
    };

    var inspection = Inspection{};
    inspection.frame_count = 1;
    inspection.cleanup_frames = 1;
    inspection.frames[0] = .{
        .frame_pointer = 0x8010,
        .stack_pointer = 0x8008,
        .mode = .rbp_frame,
        .cleanup_landing_pad = 0x1111,
    };

    var state = FakeState{};
    var engine = Engine{};
    try std.testing.expect(engine.installPhaseTwo(&state, &inspection, 0x4000));
    try std.testing.expectEqual(@as(u64, 0x1111), state.regs.rip);
    try std.testing.expect(!engine.resumePhaseTwo(&state));
    try std.testing.expect(engine.exhaustedWithoutHandler());
}

test "LSDA inspection distinguishes cleanup and typed catch landing pads" {
    const FakeState = struct {
        const Symbol = struct {
            name: []const u8,
        };
        const Metadata = struct {
            const Binding = struct {
                address: u64,
                name: []const u8,
            };

            bindings: []const Binding = &.{},

            pub fn nearestSymbol(_: @This(), _: u64) ?Symbol {
                return null;
            }
        };

        data: []const u8,
        metadata: Metadata = .{},

        pub fn guestMemoryConst(self: @This(), address: u64, count: u64) ?[]const u8 {
            if (address != 0x2000) return null;
            return self.data[0..@min(self.data.len, @as(usize, @intCast(count)))];
        }

        pub fn guestCString(_: @This(), _: u64, _: usize) ?[]const u8 {
            return null;
        }

        pub fn read64(_: @This(), _: u64) u64 {
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
    var test_engine = Engine{};
    const cleanup = findLandingPad(&test_engine, FakeState{ .data = &cleanup_lsda }, frame, 0x1005, 0x3000).?;
    try std.testing.expect(!cleanup.handles_exception);
    try std.testing.expectEqual(@as(u64, 0x1020), cleanup.address);

    var catch_lsda = [_]u8{
        0xFF, 0x00, 0x10, 0x01, 0x04, 0x00, 0x10, 0x20, 0x01, 0x01, 0x00,
        0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    const handler = findLandingPad(&test_engine, FakeState{ .data = &catch_lsda }, frame, 0x1005, 0x3000).?;
    try std.testing.expect(handler.handles_exception);
    try std.testing.expectEqual(@as(i64, 1), handler.selector);
    try std.testing.expectEqual(@as(u64, 0x1020), handler.address);

    const catch_all_lsda = [_]u8{
        0xFF, 0x9B, 0x0D, 0x01, 0x04, 0x00, 0x10, 0x20, 0x01,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    const catch_all = findLandingPad(&test_engine, FakeState{ .data = &catch_all_lsda }, frame, 0x1005, 0x3000).?;
    try std.testing.expect(catch_all.handles_exception);
    try std.testing.expect(catch_all.catch_all);
    try std.testing.expectEqual(@as(i64, 1), catch_all.selector);
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
