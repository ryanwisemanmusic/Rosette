const process = @import("../../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const guest_observation = @import("guest_observation.zig");
const MILESTONE_REFRESH = guest_observation.MILESTONE_REFRESH;
const MILESTONE_SWAP = guest_observation.MILESTONE_SWAP;
const MEM_BASE = __ProcessInternals._MEM_BASE;
const Op = process.Op;
const PPC_CONTEXT_VIRTUAL_MEMBASE = __ProcessInternals._PPC_CONTEXT_VIRTUAL_MEMBASE;
const RegId = process.RegId;
const SYNTHETIC_WINDOWS_EXCEPTION_RETURN = __ProcessInternals._SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
const WINDOWS_CLOCK_POLL_YIELD_READS = __ProcessInternals._WINDOWS_CLOCK_POLL_YIELD_READS;
const WINDOWS_EVENT_PUMP_STRIDE = __ProcessInternals._WINDOWS_EVENT_PUMP_STRIDE;
const WINDOWS_FILETIME_UNIX_EPOCH = __ProcessInternals._WINDOWS_FILETIME_UNIX_EPOCH;
const WINDOWS_GUEST_CLOCK_HZ = process.WINDOWS_GUEST_CLOCK_HZ;
const WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE = __ProcessInternals._WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE;
const WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND = process.WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
const WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP = __ProcessInternals._WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP;
const WINDOWS_GUEST_FILETIME_BASE = __ProcessInternals._WINDOWS_GUEST_FILETIME_BASE;
const WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM = __ProcessInternals._WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM;
const WINDOWS_PTHREAD_ETIMEDOUT = __ProcessInternals._WINDOWS_PTHREAD_ETIMEDOUT;
const WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT = __ProcessInternals._WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT;
const WindowsExecutableRange = process.WindowsExecutableRange;
const WindowsGuestThread = __ProcessInternals._WindowsGuestThread;
const WindowsGuestThreadStatus = __ProcessInternals._WindowsGuestThreadStatus;
const XENIA_GLOBAL_MUTEX_OWNER_OFFSET = __ProcessInternals._XENIA_GLOBAL_MUTEX_OWNER_OFFSET;
const XENIA_GLOBAL_MUTEX_RECURSION_OFFSET = __ProcessInternals._XENIA_GLOBAL_MUTEX_RECURSION_OFFSET;
const XeniaGlobalLend = __ProcessInternals._XeniaGlobalLend;
const block_jit = __ProcessInternals._block_jit;
const guestMilestoneFilterBit = __ProcessInternals._guestMilestoneFilterBit;
const guest_clock = __ProcessInternals._guest_clock;
const guest_page_protection = __ProcessInternals._guest_page_protection;
const log = __ProcessInternals._log;
const milestone_slot_collision = __ProcessInternals._milestone_slot_collision;
const parallel_metrics = __ProcessInternals._parallel_metrics;
const ppcContextGpr = __ProcessInternals._ppcContextGpr;
const std = __ProcessInternals._std;
const testing = std.testing;
const tso_memory = __ProcessInternals._tso_memory;
const x64_linux_runtime = __ProcessInternals._x64_linux_runtime;
const xbox_critical_section = __ProcessInternals._xbox_critical_section;
const xenia_guest_milestone_map = __ProcessInternals._xenia_guest_milestone_map;
const sleepForTest = @import("support.zig").sleepForTest;
const ElfState = process.ElfState;
const decodeInsn = __ProcessInternals._decodeInsn;

fn prepareWindowsCodecvtCall(
    state: *ElfState,
    entry: u64,
    stack: u64,
    return_rip: u64,
    facet: u64,
    conversion_state: u64,
    from: u64,
    from_end: u64,
    from_next_ref: u64,
    to: u64,
    to_end: u64,
    to_next_ref: u64,
) void {
    state.windows_runtime_enabled = true;
    state.configureWindowsCodecvtInEntry(entry);
    state.regs.rip = entry;
    state.regs.rsp = stack;
    state.regs.rcx = facet;
    state.regs.rdx = conversion_state;
    state.regs.r8 = from;
    state.regs.r9 = from_end;
    state.write64(stack, return_rip);
    state.write64(stack + 0x28, from_next_ref);
    state.write64(stack + 0x30, to);
    state.write64(stack + 0x38, to_end);
    state.write64(stack + 0x40, to_next_ref);
}

test "Windows PE codecvt do_in converts the portable path and supplementary UTF-8" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const entry = MEM_BASE + 0xB00;
    const return_rip = MEM_BASE + 0xA80;
    const facet = state.guestAlloc(0x20, 8).?;
    const conversion_state = state.guestAlloc(4, 4).?;
    const stack_allocation = state.guestAlloc(0x50, 16).?;
    const stack = stack_allocation + 8;
    const from_next_ref = state.guestAlloc(8, 8).?;
    const to_next_ref = state.guestAlloc(8, 8).?;
    const input_bytes = "portable.txt \xC3\xA9 \xF0\x9F\x98\x80";
    const input = state.guestAlloc(input_bytes.len, 1).?;
    for (input_bytes, 0..) |byte, index| state.write8(input + @as(u64, @intCast(index)), byte);
    const expected = [_]u16{ 'p', 'o', 'r', 't', 'a', 'b', 'l', 'e', '.', 't', 'x', 't', ' ', 0x00e9, ' ', 0xd83d, 0xde00 };
    const output = state.guestAlloc(expected.len * 2, 2).?;
    state.write32(facet + 0x18, 0x10ffff);
    state.write32(facet + 0x1c, 0);
    state.write32(conversion_state, 0);
    prepareWindowsCodecvtCall(
        &state,
        entry,
        stack,
        return_rip,
        facet,
        conversion_state,
        input,
        input + input_bytes.len,
        from_next_ref,
        output,
        output + expected.len * 2,
        to_next_ref,
    );

    state.windows_pthread_cond_wait_entry = MEM_BASE + 0xC00;
    state.windows_pthread_cond_signal_entry = MEM_BASE + 0xD00;
    state.windows_pthread_cond_broadcast_entry = MEM_BASE + 0xE00;
    state.configureWindowsUtf8FindAnyOfEntry(MEM_BASE + 0xF00);
    state.configureWindowsCodecvtInEntry(entry);
    state.configureWindowsUtf8CountEntry(MEM_BASE + 0x1100);
    try testing.expect(state.windows_compat_hook_points.contains(entry));
    try testing.expect(state.windows_compat_hook_points.contains(MEM_BASE + 0xC00));
    try testing.expect(state.windows_compat_hook_points.contains(MEM_BASE + 0xD00));
    try testing.expect(state.windows_compat_hook_points.contains(MEM_BASE + 0xE00));
    try testing.expect(state.windows_compat_hook_points.contains(MEM_BASE + 0xF00));
    try testing.expect(state.windows_compat_hook_points.contains(MEM_BASE + 0x1100));
    state.rebuildBlockJitHookFilter();
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, entry));
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, MEM_BASE + 0x1100));
    try testing.expect(x64_linux_runtime.tryWindowsGuestCompatibility(&state));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(stack + 8, state.regs.rsp);
    try testing.expectEqual(input + input_bytes.len, state.read64(from_next_ref));
    try testing.expectEqual(output + expected.len * 2, state.read64(to_next_ref));
    for (expected, 0..) |unit, index| {
        try testing.expectEqual(unit, state.read16(output + @as(u64, @intCast(index * 2))));
    }
}

test "Windows PE codecvt do_in preserves partial and invalid UTF-8 positions" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    const entry = MEM_BASE + 0xB00;
    const return_rip = MEM_BASE + 0xA80;
    const facet = state.guestAlloc(0x20, 8).?;
    const conversion_state = state.guestAlloc(4, 4).?;
    const stack_allocation = state.guestAlloc(0x50, 16).?;
    const stack = stack_allocation + 8;
    const from_next_ref = state.guestAlloc(8, 8).?;
    const to_next_ref = state.guestAlloc(8, 8).?;
    const input_bytes = "A\xF0\x9F\x98\x80B";
    const input = state.guestAlloc(input_bytes.len, 1).?;
    for (input_bytes, 0..) |byte, index| state.write8(input + @as(u64, @intCast(index)), byte);
    const output = state.guestAlloc(4, 2).?;
    state.write32(facet + 0x18, 0x10ffff);
    state.write32(facet + 0x1c, 0);
    state.write32(conversion_state, 0);
    prepareWindowsCodecvtCall(
        &state,
        entry,
        stack,
        return_rip,
        facet,
        conversion_state,
        input,
        input + input_bytes.len,
        from_next_ref,
        output,
        output + 2,
        to_next_ref,
    );
    try testing.expect(x64_linux_runtime.tryWindowsGuestCompatibility(&state));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(input + 1, state.read64(from_next_ref));
    try testing.expectEqual(output + 2, state.read64(to_next_ref));
    try testing.expectEqual(@as(u16, 'A'), state.read16(output));

    const invalid_bytes = [_]u8{ 0xed, 0xa0, 0x80 };
    const invalid_input = state.guestAlloc(invalid_bytes.len, 1).?;
    for (invalid_bytes, 0..) |byte, index| state.write8(invalid_input + @as(u64, @intCast(index)), byte);
    const invalid_output = state.guestAlloc(8, 2).?;
    const next_stack = stack_allocation + 8;
    prepareWindowsCodecvtCall(
        &state,
        entry,
        next_stack,
        return_rip,
        facet,
        conversion_state,
        invalid_input,
        invalid_input + invalid_bytes.len,
        from_next_ref,
        invalid_output,
        invalid_output + 8,
        to_next_ref,
    );
    try testing.expect(x64_linux_runtime.tryWindowsGuestCompatibility(&state));
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
    try testing.expectEqual(invalid_input, state.read64(from_next_ref));
    try testing.expectEqual(invalid_output, state.read64(to_next_ref));

    const invalid_prefix = [_]u8{ 0xf0, 0x28 };
    const invalid_prefix_input = state.guestAlloc(invalid_prefix.len, 1).?;
    for (invalid_prefix, 0..) |byte, index| state.write8(invalid_prefix_input + @as(u64, @intCast(index)), byte);
    prepareWindowsCodecvtCall(
        &state,
        entry,
        stack,
        return_rip,
        facet,
        conversion_state,
        invalid_prefix_input,
        invalid_prefix_input + invalid_prefix.len,
        from_next_ref,
        invalid_output,
        invalid_output + 8,
        to_next_ref,
    );
    try testing.expect(x64_linux_runtime.tryWindowsGuestCompatibility(&state));
    try testing.expectEqual(@as(u64, 2), state.regs.rax);
    try testing.expectEqual(invalid_prefix_input, state.read64(from_next_ref));
    try testing.expectEqual(invalid_output, state.read64(to_next_ref));
}

test "Windows PE UTF-8 count probe reports malformed input and preserves guest state" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const entry = MEM_BASE + 0x1100;
    const data_bytes = "config value \x90 suffix";
    const data = state.guestAlloc(data_bytes.len, 1).?;
    const view = state.guestAlloc(16, 8).?;
    const stack = state.guestAlloc(8, 8).?;
    for (data_bytes, 0..) |byte, index| state.write8(data + @as(u64, @intCast(index)), byte);
    // This Xenia PE's MinGW string_view representation is {length, data}.
    state.write64(view, data_bytes.len);
    state.write64(view + 8, data);
    state.write64(stack, MEM_BASE + 0xA80);
    state.configureWindowsUtf8CountEntry(entry);
    state.regs.rip = entry;
    state.regs.rsp = stack;
    state.regs.rcx = view;
    state.regs.rax = 0x1234;

    try testing.expect(!x64_linux_runtime.tryWindowsGuestCompatibility(&state));
    try testing.expectEqual(entry, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.windows_utf8_count_events);
    try testing.expectEqual(@as(u64, 1), state.windows_utf8_count_invalid_events);
}

test "Windows PE C++ throw observer ties invalid UTF-8 to its source file without consuming the throw" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const next_entry = MEM_BASE + 0x1200;
    const consumer_entry = MEM_BASE + 0x1400;
    const throw_entry = MEM_BASE + 0x1500;
    const symbols = guest_observation.TestSymbolTable{ .entries = &.{
        .{ .address = next_entry, .name = "utf8::next" },
        .{ .address = consumer_entry, .name = "toml::v3::impl::utf8_reader::read" },
        .{ .address = throw_entry, .name = "__cxa_throw" },
    } };
    state.installGuestSymbolResolver(symbols.resolver(), 3, 100);

    const thrown_object = state.guestAlloc(0x20, 8).?;
    const type_info = state.guestAlloc(0x20, 8).?;
    const type_name_text = "N4utf812invalid_utf8E\x00";
    const type_name = state.guestAlloc(type_name_text.len, 1).?;
    for (type_name_text, 0..) |byte, index| state.write8(type_name + @as(u64, @intCast(index)), byte);
    state.write64(type_info + 8, type_name);
    state.write8(thrown_object + 8, 0x90);

    const source = state.guestAlloc(32, 1).?;
    for (0..32) |index| state.write8(source + @as(u64, @intCast(index)), 'a');
    state.write8(source + 4, 0x90);
    const iterator_ref = state.guestAlloc(8, 8).?;
    state.write64(iterator_ref, source + 4);
    state.noteWindowsFileReadProvenance(source, 32, 0x400, "read", "recent.toml");

    const stack = state.guestAlloc(0x80, 16).? + 8;
    state.write64(stack, next_entry + 0x69);
    state.write64(stack + 0x38, iterator_ref);
    state.write64(stack + 0x40, consumer_entry + 0x22);
    state.configureWindowsCxaThrowEntry(throw_entry);
    try testing.expect(state.windows_compat_hook_points.contains(throw_entry));
    state.rebuildBlockJitHookFilter();
    try testing.expect(block_jit.hookFilterHas(&state.block_jit_hook_filter, throw_entry));

    state.regs.rip = throw_entry;
    state.regs.rsp = stack;
    state.regs.rcx = thrown_object;
    state.regs.rdx = type_info;
    state.regs.rsi = iterator_ref;
    state.regs.rax = 0x1234;
    try testing.expect(!x64_linux_runtime.tryWindowsGuestCompatibility(&state));

    try testing.expectEqual(throw_entry, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.windows_cxa_throw_events);
    try testing.expectEqual(@as(u64, 1), state.windows_invalid_utf8_throw_events);
    try testing.expectEqual(@as(u64, 1), state.windows_invalid_utf8_source_matches);
    try testing.expectEqual(source + 4, state.windows_invalid_utf8_last_source_address);
    try testing.expectEqual(@as(u8, 0x90), state.windows_invalid_utf8_last_source_byte);
    try testing.expect(state.windows_invalid_utf8_last_source_byte_matches_exception);
    try testing.expect(state.windows_invalid_utf8_last_iterator_ref_consistent);
    try testing.expectEqual(consumer_entry + 0x22, state.windows_invalid_utf8_last_consumer);
    try testing.expectEqual(@as(?u64, 0x404), state.windows_invalid_utf8_last_file_offset);
    try testing.expectEqual(@as(?u64, 0x404), state.windowsFileReadProvenanceAt(source + 4).?.fileOffsetAt(source + 4));
}

test "Windows PE C++ throw observer accepts only a cursor candidate matching the thrown octet" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const next_entry = MEM_BASE + 0x1200;
    const consumer_entry = MEM_BASE + 0x1400;
    const throw_entry = MEM_BASE + 0x1500;
    const symbols = guest_observation.TestSymbolTable{ .entries = &.{
        .{ .address = next_entry, .name = "utf8::next" },
        .{ .address = consumer_entry, .name = "xe::utf8::count" },
        .{ .address = throw_entry, .name = "__cxa_throw" },
    } };
    state.installGuestSymbolResolver(symbols.resolver(), 3, 100);

    const thrown_object = state.guestAlloc(0x20, 8).?;
    const type_info = state.guestAlloc(0x20, 8).?;
    const type_name_text = "N4utf812invalid_utf8E\x00";
    const type_name = state.guestAlloc(type_name_text.len, 1).?;
    for (type_name_text, 0..) |byte, index| state.write8(type_name + @as(u64, @intCast(index)), byte);
    state.write64(type_info + 8, type_name);
    state.write8(thrown_object + 8, 0x90);

    const source = state.guestAlloc(32, 1).?;
    for (0..32) |index| state.write8(source + @as(u64, @intCast(index)), 'a');
    state.write8(source + 8, 0x90);
    const live_iterator_ref = state.guestAlloc(8, 8).?;
    state.write64(live_iterator_ref, source + 8);

    const stack = state.guestAlloc(0x80, 16).? + 8;
    state.write64(stack, next_entry + 0x69);
    // The latest Xenia run had a readable RSP+0x38 word but it was a cursor
    // value, not a pointer to an iterator reference. Preserve that shape so
    // the observer must reject it and select live RSI by exact octet match.
    state.write64(stack + 0x38, source + 9);
    state.write64(stack + 0x40, consumer_entry + 0x22);
    state.configureWindowsCxaThrowEntry(throw_entry);
    state.rebuildBlockJitHookFilter();

    state.regs.rip = throw_entry;
    state.regs.rsp = stack;
    state.regs.rcx = thrown_object;
    state.regs.rdx = type_info;
    state.regs.rsi = live_iterator_ref;
    state.regs.rax = 0x1234;
    try testing.expect(!x64_linux_runtime.tryWindowsGuestCompatibility(&state));

    try testing.expectEqual(throw_entry, state.regs.rip);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 0x1234), state.regs.rax);
    try testing.expectEqual(@as(u64, 1), state.windows_invalid_utf8_throw_events);
    try testing.expectEqual(source + 8, state.windows_invalid_utf8_last_source_address);
    try testing.expectEqual(@as(u8, 0x90), state.windows_invalid_utf8_last_source_byte);
    try testing.expect(state.windows_invalid_utf8_last_source_byte_matches_exception);
    try testing.expect(!state.windows_invalid_utf8_last_iterator_ref_consistent);
    try testing.expect(!state.windows_invalid_utf8_last_saved_cursor_matches_exception);
    try testing.expect(state.windows_invalid_utf8_last_live_cursor_matches_exception);
    try testing.expectEqual(consumer_entry + 0x22, state.windows_invalid_utf8_last_consumer);
}

test "Windows filesystem bootstrap supplies guest-owned executable and user paths" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x980;
    const executable_output = state.guestAlloc(8, 8).?;
    state.regs.rcx = executable_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_get_wpgmptr", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    const executable_path = state.read64(executable_output);
    try testing.expect(executable_path != 0);
    for ([_]u16{ 'C', ':', '\\', 'x', 'e', 'n', 'i', 'a', '\\', 'x', 'e', 'n', 'i', 'a', '_', 'c', 'a', 'n', 'a', 'r', 'y', '.', 'e', 'x', 'e', 0 }, 0..) |unit, index| {
        try testing.expectEqual(unit, state.read16(executable_path + @as(u64, @intCast(index * 2))));
    }

    const known_folder_output = state.guestAlloc(8, 8).?;
    state.regs.r9 = known_folder_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "shell32.dll", "SHGetKnownFolderPath", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    const known_folder_path = state.read64(known_folder_output);
    try testing.expect(known_folder_path != 0);
    for ([_]u16{ 'C', ':', '\\', 'x', 'e', 'n', 'i', 'a', '\\', 'D', 'o', 'c', 'u', 'm', 'e', 'n', 't', 's', 0 }, 0..) |unit, index| {
        try testing.expectEqual(unit, state.read16(known_folder_path + @as(u64, @intCast(index * 2))));
    }

    const wide_string = state.guestAlloc(32, 2).?;
    for ("C:\\xenia", 0..) |unit, index| {
        state.write16(wide_string + @as(u64, @intCast(index * 2)), unit);
    }
    state.write16(wide_string + 16, 0);
    state.regs.rcx = wide_string;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "wcslen", return_rip));
    try testing.expectEqual(@as(u64, 8), state.regs.rax);
}

test "every SHGetKnownFolderPath result is the caller's to free exactly once" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0x980;
    const fonts_guid = [_]u8{ 0xB7, 0x8C, 0x22, 0xFD, 0x11, 0xAE, 0xE3, 0x4A, 0x86, 0x4C, 0x16, 0xF3, 0x91, 0x0A, 0xB8, 0xFE };
    const guid = state.guestAlloc(16, 8).?;
    for (fonts_guid, 0..) |byte, index| state.write8(guid + index, byte);
    const output = state.guestAlloc(8, 8).?;
    var results: [2]u64 = undefined;
    for (&results) |*result| {
        state.regs.rcx = guid;
        state.regs.r9 = output;
        try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "shell32.dll", "SHGetKnownFolderPath", return_rip));
        try testing.expectEqual(@as(u64, 0), state.regs.rax);
        result.* = state.read64(output);
        try testing.expectEqual(@as(u16, 'C'), state.read16(result.*));
        // Xenia's font probes free each result with CoTaskMemFree.
        state.regs.rcx = result.*;
        try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ole32.dll", "CoTaskMemFree", return_rip));
    }
    try testing.expect(results[0] != results[1]);
    try testing.expectEqual(@as(u64, 0), state.windows_heap_double_frees);
}

test "a parallel raw view is served for data and refused only for fetched code" {
    var state = ElfState.initWithMemory(testing.allocator, 0x10000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const code = state.mem_base + 0x1000;
    state.configureWindowsExecutableRanges(&[_]WindowsExecutableRange{
        .{ .guest_base = code, .length = 0x100 },
    });
    const allocation_base: u64 = 0x2_0000_0000;
    try testing.expect(state.createWindowsVirtualAllocation(allocation_base, 0x10000));
    state.parallel_guest_execution = true;

    // An out-parameter on a data page. Refusing this view is what dropped
    // the Vulkan adapter's properties on 2026-09-30.
    const data = state.mem_base + 0x4000;
    const view = state.guestMemory(data, 8) orelse return error.DataViewRefused;
    std.mem.writeInt(u64, view[0..8], 0x1122_3344_5566_7788, .little);
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), state.read64(data));

    // Executable bytes, including a borrow that only straddles into them,
    // have to move their generation after the write.
    try testing.expect(state.guestMemory(code + 0x10, 4) == null);
    try testing.expect(state.guestMemory(code - 2, 4) == null);
    try testing.expectEqual(@as(u64, 2), state.parallel_code_borrow_refusals.load(.monotonic));
    const generation = ElfState.loadCodeGeneration(&state.windows_image_code_generation);
    try testing.expect(state.copyToGuest(code + 0x10, &.{ 0x90, 0x90, 0x90, 0xC3 }));
    try testing.expect(ElfState.loadCodeGeneration(&state.windows_image_code_generation) != generation);
    try testing.expectEqual(@as(u8, 0xC3), state.read8(code + 0x13));

    // A mapping is data until an executor fetches from it.
    try testing.expect(state.guestMemory(allocation_base + 0x40, 8) != null);
    const slot = state.windows_mapped_ranges.find(allocation_base, 1).?.slot;
    state.windows_virtual_allocations[slot].code_fetched = true;
    try testing.expect(state.guestMemory(allocation_base + 0x40, 8) == null);
    try testing.expectEqual(@as(u64, 3), state.parallel_code_borrow_refusals.load(.monotonic));
}

test "parallel runtime calls fill the out-parameters the 2026-09-30 run lost" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.parallel_guest_execution = true;
    const return_rip = MEM_BASE + 0x980;

    // Xenia's font probe: E_INVALIDARG left *ppszPath unwritten, and
    // LoadWindowsFont then freed the stale stack word it held.
    const fonts_guid = [_]u8{ 0xB7, 0x8C, 0x22, 0xFD, 0x11, 0xAE, 0xE3, 0x4A, 0x86, 0x4C, 0x16, 0xF3, 0x91, 0x0A, 0xB8, 0xFE };
    const guid = state.guestAlloc(16, 8).?;
    for (fonts_guid, 0..) |byte, index| state.write8(guid + index, byte);
    const path_output = state.guestAlloc(8, 8).?;
    state.regs.rcx = guid;
    state.regs.r9 = path_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "SHELL32.dll", "SHGetKnownFolderPath", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax); // S_OK
    const path = state.read64(path_output);
    try testing.expectEqual(@as(u16, 'C'), state.read16(path));
    state.regs.rcx = path;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ole32.dll", "CoTaskMemFree", return_rip));
    try testing.expectEqual(@as(u64, 0), state.windows_heap_double_frees);

    // `GetPersistentEmulatorFlags`: RegOpenKeyA answered
    // ERROR_INVALID_PARAMETER, then RegCreateKeyA did, so RegSetValueExA,
    // RegFlushKey and RegCloseKey all ran on a null key.
    const subkey = state.guestAlloc(32, 1).?;
    const key_name = "Software\\Xenia";
    for (key_name, 0..) |character, index| state.write8(subkey + @as(u64, @intCast(index)), character);
    state.write8(subkey + key_name.len, 0);
    const key_output = state.guestAlloc(8, 8).?;
    state.regs.rcx = 0xFFFF_FFFF_8000_0001; // HKEY_CURRENT_USER
    state.regs.rdx = subkey;
    state.regs.r8 = key_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegCreateKeyA", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax); // ERROR_SUCCESS
    const key = state.read64(key_output);
    try testing.expect(key != 0);
    state.regs.rcx = key;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ADVAPI32.dll", "RegCloseKey", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
}

test "the parallel executor reports the host's processors and the cooperative one reports one" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = MEM_BASE + 0x980;
    const info = state.guestAlloc(48, 8).?;
    const process_mask = state.guestAlloc(8, 8).?;
    const system_mask = state.guestAlloc(8, 8).?;

    state.regs.rcx = info;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "GetSystemInfo", return_rip));
    try testing.expectEqual(@as(u32, 1), state.read32(info + 32));

    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const expected = ElfState.guestProcessorMask();
    state.regs.rcx = info;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "GetSystemInfo", return_rip));
    try testing.expectEqual(@as(u32, @popCount(expected)), state.read32(info + 32));
    try testing.expectEqual(expected, state.read64(info + 24));

    // winpthreads counts these bits for std::thread::hardware_concurrency;
    // the 2026-09-30 run refused the call 133 times, which reads as one.
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = process_mask;
    state.regs.r8 = system_mask;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "GetProcessAffinityMask", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(expected, state.read64(process_mask));
    try testing.expectEqual(expected, state.read64(system_mask));
}

test "Windows path shims publish wide paths before returning under hybrid TSO" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.parallel_guest_execution = true;

    const return_rip = MEM_BASE + 0xA80;
    const executable_output = state.guestAlloc(8, 8).?;
    const source = state.guestAlloc(64, 2).?;
    const destination = state.guestAlloc(128, 2).?;
    const file_part = state.guestAlloc(8, 8).?;
    for ("settings.toml", 0..) |unit, index| {
        state.write16(source + @as(u64, @intCast(index * 2)), unit);
    }
    state.write16(source + 26, 0);

    var buffer: tso_memory.StoreBuffer = .{};
    const prior_buffer = tso_memory.setActiveStoreBuffer(&buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);
    const prior_coordinated = tso_memory.setCoordinatedGuestAccess(true);
    defer _ = tso_memory.setCoordinatedGuestAccess(prior_coordinated);

    state.regs.rcx = executable_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_get_wpgmptr", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(usize, 0), buffer.pendingCount());

    const executable_output_offset: usize = @intCast(state.addrToOffset(executable_output).?);
    const executable_path = std.mem.readInt(u64, state.mem[executable_output_offset..][0..8], .little);
    const executable_path_offset: usize = @intCast(state.addrToOffset(executable_path).?);
    const executable_units = [_]u16{ 'C', ':', '\\', 'x', 'e', 'n', 'i', 'a', '\\', 'x', 'e', 'n', 'i', 'a', '_', 'c', 'a', 'n', 'a', 'r', 'y', '.', 'e', 'x', 'e', 0 };
    for (executable_units, 0..) |unit, index| {
        const offset = executable_path_offset + index * 2;
        try testing.expectEqual(unit, std.mem.readInt(u16, state.mem[offset..][0..2], .little));
    }

    state.regs.rcx = source;
    state.regs.rdx = 64;
    state.regs.r8 = destination;
    state.regs.r9 = file_part;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFullPathNameW", return_rip));
    const destination_offset: usize = @intCast(state.addrToOffset(destination).?);
    const expected_path = "C:\\xenia\\settings.toml";
    for (expected_path, 0..) |unit, index| {
        const offset = destination_offset + index * 2;
        try testing.expectEqual(@as(u16, unit), std.mem.readInt(u16, state.mem[offset..][0..2], .little));
    }
    try testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, state.mem[destination_offset + expected_path.len * 2 ..][0..2], .little));
    try testing.expectEqual(destination + 18, state.read64(file_part));
    try testing.expectEqual(@as(usize, 0), buffer.pendingCount());
}

test "Windows path and XInput contracts preserve guest ABI semantics" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;

    const return_rip = MEM_BASE + 0xA00;
    const source = state.guestAlloc(32, 1).?;
    const destination = state.guestAlloc(128, 1).?;
    const file_part = state.guestAlloc(8, 8).?;
    for ("config.toml", 0..) |character, index| state.write8(source + @as(u64, @intCast(index)), character);
    state.write8(source + 11, 0);
    state.regs.rcx = source;
    state.regs.rdx = 128;
    state.regs.r8 = destination;
    state.regs.r9 = file_part;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFullPathNameA", return_rip));
    try testing.expectEqualStrings("C:\\xenia\\config.toml", std.mem.sliceTo(state.mem[@intCast(state.addrToOffset(destination).?)..], 0));
    try testing.expectEqual(destination + 9, state.read64(file_part));
    try testing.expectEqual(return_rip, state.regs.rip);

    const state_output = state.guestAlloc(16, 4).?;
    state.regs.rcx = 0;
    state.regs.rdx = state_output;
    state.regs.r8 = 0;
    state.regs.r9 = 0;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "XInputGetState", return_rip));
    try testing.expectEqual(@as(u64, 1167), state.regs.rax);
    for (state.mem[@intCast(state.addrToOffset(state_output).?)..][0..16]) |byte| try testing.expectEqual(@as(u8, 0), byte);
}

test "Windows PE filesystem bridge reads only from its configured root" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // The check graph runs test artifacts from both the repository root and
    // the build directory. Keep the fixture in Zig's per-run temporary tree
    // so this contract tests the configured-root boundary rather than an
    // incidental process working directory.
    var temp_dir = testing.tmpDir(.{});
    defer temp_dir.cleanup();
    try temp_dir.dir.writeFile(testing.io, .{
        .sub_path = "probe.zig",
        .data = "windows runtime probe\n",
    });
    var working_directory_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const working_directory = try std.fmt.bufPrint(
        &working_directory_buffer,
        ".zig-cache/tmp/{s}",
        .{temp_dir.sub_path[0..]},
    );
    state.windows_runtime_enabled = true;
    state.windows_host_io = testing.io;
    state.windows_host_working_directory = working_directory;

    const return_rip = MEM_BASE + 0xB00;
    state.regs.rsp = MEM_BASE + 0x1000;
    const path = state.guestAlloc(64, 1).?;
    for ("C:\\xenia\\probe.zig", 0..) |character, index| state.write8(path + @as(u64, @intCast(index)), character);
    state.write8(path + 18, 0);
    state.regs.rcx = path;
    state.regs.rdx = 0x8000_0000; // GENERIC_READ
    state.regs.r8 = 1; // FILE_SHARE_READ
    state.regs.r9 = 0;
    state.write64(state.regs.rsp + 32, 3); // OPEN_EXISTING
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CreateFileA", return_rip));
    const handle = state.regs.rax;
    try testing.expect(handle != std.math.maxInt(u64));

    const buffer = state.guestAlloc(16, 1).?;
    const completed = state.guestAlloc(4, 4).?;
    state.regs.rcx = handle;
    state.regs.rdx = buffer;
    state.regs.r8 = 8;
    state.regs.r9 = completed;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "ReadFile", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expect(state.read32(completed) > 0);

    state.regs.rcx = handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CloseHandle", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    // The Windows PE is built with MinGW's 56-byte `_stat64` ABI: the
    // 64-bit size is at byte 24, after the naturally aligned `st_rdev`.
    // Keep this assertion close to the confined-file test so a filesystem
    // probe cannot regress into a successful call with a malformed record.
    const stat_output = state.guestAlloc(56, 8).?;
    state.regs.rcx = path;
    state.regs.rdx = stat_output;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ucrtbase.dll", "_stat64", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u16, 0x8000), state.read16(stat_output + 6));
    try testing.expectEqual(@as(u64, "windows runtime probe\n".len), state.read64(stat_output + 24));

    // std::filesystem may hand the Win32 bridge the same virtual mount with
    // forward separators after normalizing a path.  The confined C:\xenia
    // authority must accept both spellings.
    for ("C:/xenia/probe.zig", 0..) |character, index| state.write8(path + @as(u64, @intCast(index)), character);
    state.write8(path + 18, 0);
    state.regs.rcx = path;
    state.regs.rdx = 0x8000_0000;
    state.regs.r8 = 1;
    state.regs.r9 = 0;
    state.write64(state.regs.rsp + 32, 3);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CreateFileA", return_rip));
    const forward_slash_handle = state.regs.rax;
    try testing.expect(forward_slash_handle != std.math.maxInt(u64));
    state.regs.rcx = forward_slash_handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "CloseHandle", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    const outside = state.guestAlloc(64, 1).?;
    for ("C:\\Windows\\System32\\secret", 0..) |character, index| state.write8(outside + @as(u64, @intCast(index)), character);
    state.write8(outside + 29, 0);
    state.regs.rcx = outside;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "GetFileAttributesA", return_rip));
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rax);

    const pattern = state.guestAlloc(64, 1).?;
    for ("C:\\xenia\\*.zig", 0..) |character, index| state.write8(pattern + @as(u64, @intCast(index)), character);
    state.write8(pattern + 15, 0);
    const find_data = state.guestAlloc(592, 8).?;
    state.regs.rcx = pattern;
    state.regs.rdx = find_data;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "FindFirstFileA", return_rip));
    const find_handle = state.regs.rax;
    try testing.expect(find_handle != std.math.maxInt(u64));
    try testing.expect(state.read32(find_data) == 0x80 or state.read32(find_data) == 0x10);
    state.regs.rcx = find_handle;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "FindClose", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);

    // DeleteFileW must perform the real, confined unlink.  The MinGW
    // filesystem facade uses this during image/cache cleanup; returning a
    // generic "not implemented" FALSE here is promoted to a C++ exception.
    const wide_path = state.guestAlloc(128, 2).?;
    for ("C:\\xenia\\probe.zig", 0..) |character, index| {
        state.write16(wide_path + @as(u64, @intCast(index * 2)), character);
    }
    state.write16(wide_path + 36, 0);
    state.regs.rcx = wide_path;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "DeleteFileW", return_rip));
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u32, 0), state.windows_last_error);

    // A second delete is a normal Win32 miss, not a Rosetta refusal.  This is
    // the exact distinction the C++ error_code path relies on.
    state.regs.rcx = wide_path;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "kernel32.dll", "DeleteFileW", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 2), state.windows_last_error);
}

test "the host event pump is throttled but never skips a pending paint" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // Xenia's message loop asked 12.7 million times in one run, once per
    // ~18 guest instructions. The stride answers a few hundred times a
    // second instead.
    state.executed_steps = 0;
    _ = state.windows_graphics.pumpEventsAtStep(0, false);
    try testing.expectEqual(@as(u64, 1), state.windows_graphics.event_pump_calls);
    _ = state.windows_graphics.pumpEventsAtStep(1, false);
    _ = state.windows_graphics.pumpEventsAtStep(WINDOWS_EVENT_PUMP_STRIDE - 1, false);
    try testing.expectEqual(@as(u64, 1), state.windows_graphics.event_pump_calls);
    try testing.expectEqual(@as(u64, 2), state.windows_graphics.event_pump_skips);

    _ = state.windows_graphics.pumpEventsAtStep(WINDOWS_EVENT_PUMP_STRIDE, false);
    try testing.expectEqual(@as(u64, 2), state.windows_graphics.event_pump_calls);

    // A pending paint is the one case where a skipped pump is a skipped
    // frame, so it is never declined.
    _ = state.windows_graphics.pumpEventsAtStep(WINDOWS_EVENT_PUMP_STRIDE + 1, true);
    _ = state.windows_graphics.pumpEventsAtStep(WINDOWS_EVENT_PUMP_STRIDE + 2, true);
    try testing.expectEqual(@as(u64, 4), state.windows_graphics.event_pump_calls);
    try testing.expectEqual(@as(u64, 2), state.windows_graphics.event_pump_skips);
}

test "the guest clock is real time, and never goes backwards" {
    // It used to advance one tick per interpreted instruction against a
    // published frequency of 1 MHz, which is a machine executing one
    // instruction per microsecond. Hardware does about three thousand, so
    // every guest timeout was denominated in a clock running three thousand
    // times fast relative to the work being done: on the 2026-09-12 run
    // 102,658 of 118,015 waits timed out and two threads servicing one
    // repeating millisecond timer held forty-two percent of the interpreter.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    try testing.expect(!(state.guest_clock.source == .retired_instructions));

    // The first sample establishes the base and publishes nothing.
    state.refreshWindowsGuestClock();
    try testing.expect(state.guest_clock.base_nanos != 0 or state.guest_clock.host_unavailable);

    // Reading it repeatedly is monotonic non-decreasing. A counter that goes
    // backwards makes every `now - then` in the guest an enormous unsigned
    // interval, and every deadline in the run is computed that way.
    var previous: u64 = 0;
    for (0..64) |_| {
        state.refreshWindowsGuestClock();
        const now = state.guest_clock.ticks;
        try testing.expect(now >= previous);
        previous = now;
    }

    // Within a stride the clock is flat rather than sampled per instruction,
    // which is also what a real performance counter with finite resolution
    // does. What must never happen is the stride skipping the sample
    // entirely: a deadline is asked about at the moment it matters.
    state.guest_clock.stride = 0;
    state.refreshWindowsGuestClock();
    try testing.expectEqual(@as(u64, 0), state.guest_clock.stride);
}

test "the instruction-derived clock is still available, and is exactly one tick a step" {
    // Kept as a mode because the trade-off is real: an instruction-derived
    // clock is immune to host scheduling jitter, a host-derived one is immune
    // to how fast the interpreter happens to be. A run comparing the two
    // should not need a rebuild.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .retired_instructions;

    const before = state.guest_clock.ticks;
    for (0..1000) |_| state.advanceWindowsGuestClock();
    try testing.expectEqual(before + 1000, state.guest_clock.ticks);

    // And in this mode a refresh must not reach for the host clock at all,
    // or a test or a replay that drives the counter by hand would have its
    // value overwritten by however long it took to get there.
    state.guest_clock.ticks = 12_345;
    state.refreshWindowsGuestClock();
    try testing.expectEqual(@as(u64, 12_345), state.guest_clock.ticks);
}

test "parallel host clock sampling uses an executor-local stride" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .host_monotonic;
    state.setParallelGuestExecution(true);

    for (0..WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE - 1) |_| state.advanceWindowsGuestClock();
    try testing.expectEqual(
        WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE - 1,
        state.guest_clock_sample_steps,
    );
    state.advanceWindowsGuestClock();
    try testing.expectEqual(@as(u64, 0), state.guest_clock_sample_steps);

    state.setParallelGuestExecution(false);
}

test "translated retirement fills the private clock stride at a fraction of a step per instruction and never waits for the clock" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .host_monotonic;
    state.guest_clock.base_nanos = 1;
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);

    // A block's exit only counts: one step per
    // WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP instructions, rounded up so a
    // short block still counts.
    state.advanceWindowsGuestClockBy(WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP * (WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE - 2));
    state.advanceWindowsGuestClockBy(1);
    try testing.expectEqual(WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE - 1, state.guest_clock_sample_steps);

    // The stride fills while another executor holds the clock: this one
    // skips its sample rather than queue, and starts a new stride.
    state.guest_clock.ticks = 7;
    state.guest_clock_mutex.lock();
    state.advanceWindowsGuestClockBy(WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP);
    state.guest_clock_mutex.unlock();
    try testing.expectEqual(@as(u64, 0), state.guest_clock_sample_steps);
    try testing.expectEqual(@as(u64, 7), state.guest_clock.ticks);

    // With the clock free, a full stride samples the host and publishes.
    state.advanceWindowsGuestClockBy(WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP * WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE);
    try testing.expectEqual(@as(u64, 0), state.guest_clock_sample_steps);
    try testing.expect(state.guest_clock.ticks > 7);
    try testing.expectEqual(state.guest_clock.ticks, state.guest_clock_published_ticks.load());
}

test "a guest millisecond means the same thing to a sleeper and to a clock reader" {
    // Pin the clock's source so the test drives it. The default reads the
    // host monotonic clock, and a test that sets a tick count by hand must
    // not have it overwritten by however long the test itself took.
    // Rosette published QueryPerformanceFrequency = 1 MHz and advanced the
    // counter once per interpreted instruction, so a millisecond is a
    // thousand ticks. The wait deadline used the scheduler quantum instead -
    // a million *owner* steps - so Xenia's frame limiter asking to sleep
    // 100 ms was parked for a hundred million owner steps, about six minutes
    // of real time on the 2026-09-12 run. It never reached MarkVblank.
    try testing.expectEqual(@as(u64, 1_000_000), WINDOWS_GUEST_CLOCK_HZ);
    try testing.expectEqual(@as(u64, 1_000), WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND);
    try testing.expectEqual(
        WINDOWS_GUEST_CLOCK_HZ / 1000,
        WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND,
    );

    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .retired_instructions;
    try testing.expectEqual(WINDOWS_GUEST_CLOCK_HZ, state.windowsGuestClockHz());

    // One millisecond of guest clock is one millisecond of sleep, and both
    // are a thousand times cheaper than the scheduler quantum they used to
    // be charged at.
    const ms: u64 = 100;
    const ticks = ms * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND;
    try testing.expectEqual(@as(u64, 100_000), ticks);
    try testing.expect(ticks * 1000 == ms * WINDOWS_GUEST_THREAD_SCHEDULER_QUANTUM);
}

test "a timed wait wakes on the guest clock, not on the owner's step counter" {
    // Pin the clock's source so the test drives it. The default reads the
    // host monotonic clock, and a test that sets a tick count by hand must
    // not have it overwritten by however long the test itself took.
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.source = .retired_instructions;

    state.windows_guest_threads[2] = .{
        .status = .blocked,
        .handle = 0xC0,
        .blocked_wait_handle = 0xD0,
        .blocked_wait_timeout = 5,
        .blocked_wait_deadline = 5 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND,
    };

    // The owner racing ahead does not wake it: the owner's counter stops
    // whenever the scheduler is running workers, which is most of a run.
    state.executed_steps = 1_000_000_000;
    state.guest_clock.ticks = 4_999;
    try testing.expectEqual(@as(u64, 0), state.wakeExpiredWindowsGuestWaits());
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[2].status);

    // The guest clock reaching the deadline does.
    state.guest_clock.ticks = 5_000;
    try testing.expectEqual(@as(u64, 1), state.wakeExpiredWindowsGuestWaits());
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expect(state.windows_guest_threads[2].wait_resume_timeout);
}

test "a yield boundary ends the slice, and a Sleep parks on the guest clock" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();

    // No worker active: a yield has nobody to hand the interpreter to, and
    // must not pretend otherwise.
    state.requestWindowsGuestSliceYield();
    try testing.expect(!state.windows_guest_slice_yield_requested);
    try testing.expect(!state.parkWindowsGuestSleep(100));

    state.windows_guest_threads[4] = .{ .status = .running, .handle = 0xE0 };
    state.windows_active_guest_thread_slot = 4;

    // Xenia's logger uses disruptorplus::spin_wait_strategy, whose consumer
    // spins on an empty ring forever. The yield between spins is the only
    // thing that can end that slice.
    state.requestWindowsGuestSliceYield();
    try testing.expect(state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 1), state.windows_guest_slice_yields);
    state.requestWindowsGuestSliceYield();
    try testing.expectEqual(@as(u64, 1), state.windows_guest_slice_yields);

    // Sleep(0) is a yield by definition; Sleep(n) parks for n guest
    // milliseconds against the clock the guest itself reads.
    state.windows_guest_slice_yield_requested = false;
    try testing.expect(state.parkWindowsGuestSleep(0));
    try testing.expect(state.windows_guest_slice_yield_requested);

    state.guest_clock.ticks = 7_000;
    try testing.expect(state.parkWindowsGuestSleep(25));
    const thread = &state.windows_guest_threads[4];
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
    try testing.expectEqual(@as(u64, 0), thread.blocked_wait_handle);
    try testing.expectEqual(
        7_000 + 25 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND,
        thread.blocked_wait_deadline,
    );

    // A park with no wait object resumes after the Sleep returned, so it must
    // not be handed a wait result it never asked for.
    state.windows_active_guest_thread_slot = null;
    state.guest_clock.ticks = thread.blocked_wait_deadline;
    try testing.expectEqual(@as(u64, 1), state.wakeExpiredWindowsGuestWaits());
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, thread.status);
    try testing.expect(!thread.wait_resume);
    try testing.expect(!thread.wait_resume_timeout);
}

test "a worker that signals the owner's wait object hands its slice to the owner" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // winpthreads' mutex handoff event: auto-reset, signalled by unlock
    // only when a waiter announced itself.
    const event: u64 = 0xFFFF_F000_0000_0B01;
    const other: u64 = 0xFFFF_F000_0000_0B02;
    state.registerWindowsEvent(event, false, false);
    state.registerWindowsEvent(other, false, false);
    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xD0 };

    // The owner is not waiting on anything: a worker's signal is not a handoff.
    state.windows_active_guest_thread_slot = 3;
    try testing.expectEqual(@as(u64, 0), state.signalWindowsWaitObject(event, false));
    try testing.expect(!state.windows_guest_handoff_requested);
    _ = state.resetWindowsWaitObject(event);

    // The owner waits on `event`; a worker signalling `other` is unrelated.
    state.setOwnerWaitHandles(&.{event});
    try testing.expectEqual(@as(u64, 0), state.signalWindowsWaitObject(other, false));
    try testing.expect(!state.windows_guest_handoff_requested);

    // Signalling the owner's object ends the worker's slice, once.
    try testing.expectEqual(@as(u64, 0), state.signalWindowsWaitObject(event, false));
    try testing.expect(state.windows_guest_handoff_requested);
    try testing.expectEqual(@as(u64, 1), state.windows_owner_wait_handoffs);
    try testing.expectEqual(@as(u64, 0), state.signalWindowsWaitObject(event, false));
    try testing.expectEqual(@as(u64, 1), state.windows_owner_wait_handoffs);
    // The object stays signalled for the owner: nobody consumed it.
    try testing.expect(state.windowsWaitObjectSignaled(event));

    // The owner itself signalling is never a handoff (no worker is running).
    state.windows_guest_handoff_requested = false;
    state.windows_active_guest_thread_slot = null;
    try testing.expectEqual(@as(u64, 0), state.signalWindowsWaitObject(event, false));
    try testing.expect(!state.windows_guest_handoff_requested);
    state.windows_owner_wait_handle_count = 0;
}

test "a milestone filter hit costs one comparison, not a scan" {
    var table = guest_observation.TestSymbolTable{ .entries = &.{
        .{ .address = 0x140001000, .name = MILESTONE_REFRESH },
        .{ .address = 0x140002000, .name = MILESTONE_SWAP },
    } };
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.installGuestSymbolResolver(table.addressableResolver(), 2, 99);

    // Each armed address owns its filter bit, so a hit resolves directly.
    for (state.guest_milestone_addresses, 0..) |address, index| {
        if (address == 0) continue;
        const bit = guestMilestoneFilterBit(address);
        const slot = state.guest_milestone_slot[bit];
        try testing.expect(slot != 0);
        if (slot != milestone_slot_collision) {
            try testing.expectEqual(index, @as(usize, slot) - 1);
        }
    }

    state.noteGuestMilestoneEntry(0x140001000);
    try testing.expectEqual(@as(u64, 1), state.guestMilestoneHitsNamed(MILESTONE_REFRESH));

    // An address that collides with an armed bit but is not armed is a miss,
    // counted so a filter that stops paying for itself is visible.
    const before = state.guest_milestone_filter_misses;
    state.noteGuestMilestoneEntry(0x140001000 + (@as(u64, 1) << 16));
    try testing.expect(state.guest_milestone_filter_misses >= before);
    try testing.expectEqual(@as(u64, 1), state.guestMilestoneHitsNamed(MILESTONE_REFRESH));
}

test "title worker code-cache execution closes the owner-only first-frame evidence gap" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_code_cache_view = 0;
    state.windows_memory_views[0] = .{ .guest_base = 0xa0000000, .length = 0x100000, .mapping_index = 0, .backing_offset = 0 };
    state.windows_memory_view_count = 1;
    state.windows_active_guest_thread_slot = 0;
    state.noteWindowsTitleCodeFetch(0xa0026b6a);
    try testing.expectEqual(@as(u64, 0), state.windows_title_code_fetches);
    state.recordGuestMilestone(comptime xenia_guest_milestone_map.indexOf("_ZN2xe6kernel7XThread7ExecuteEv").?, 0x1402333b0);
    try testing.expect(state.windows_guest_threads[0].entered_xenia_title);
    state.noteWindowsTitleCodeFetch(0x14312eef0); // heap helper, not title code cache
    try testing.expectEqual(@as(u64, 0), state.windows_title_code_fetches);
    state.noteWindowsTitleCodeFetch(0xa0026b6a);
    try testing.expectEqual(@as(u64, 1), state.windows_title_code_fetches);
    const stages = state.firstFrameChainStages();
    try testing.expect(stages[7].met);
    try testing.expectEqualStrings("title_worker_code_cache_fetches", stages[7].evidence);
    // No graphics milestones are fabricated by observing a code fetch.
    try testing.expect(!state.guestOutputChainStages()[6].met);
}

test "native Vulkan refusal cannot become a modeled successful graphics call" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const Hooks = struct {
        fn refuse(_: ?*anyopaque, _: *anyopaque, _: [*]const u8, _: usize, _: u64, _: c_int) callconv(.c) c_int {
            return 0;
        }
    };
    state.windows_graphics.hooks.native_vulkan_dispatch = Hooks.refuse;
    try testing.expect(!state.tryNativeWindowsVulkan("CreateDXGIFactory1", null));
    try testing.expect(!state.terminated);
    try testing.expect(state.tryNativeWindowsVulkan("vkCreateGraphicsPipelines", null));
    try testing.expect(state.terminated);
    try testing.expectEqual(@as(u64, 0), state.windows_graphics.presents);
}

test "an SRW release hands the lock to its longest waiter instead of letting them race" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const lock_address = MEM_BASE + 0x2000;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    state.windows_guest_threads[2] = .{ .status = .running, .handle = 0x12, .thread_id = 7 };

    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));

    // Thread 7 queues first, thread 6 second.
    state.windows_active_guest_thread_slot = 2;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(lock_address));
    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(lock_address));

    state.windows_active_guest_thread_slot = 0;
    state.releaseWindowsSrwLock(lock_address);
    const lock = state.windows_srw_locks[state.windowsSrwLockIndex(lock_address).?];
    try testing.expectEqual(@as(u64, 7), lock.owner_thread_id);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);
    try testing.expectEqual(@as(u64, 1), state.windows_srw_handoffs);

    // The thread that just released it - the one that was starving the
    // compiler on the 2026-09-13 run - cannot take it back before the waiter
    // it was handed to has run.
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));

    // The waiter retries at its own call site and finds itself the owner.
    state.windows_active_guest_thread_slot = 2;
    state.windows_guest_threads[2].status = .running;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));
    state.releaseWindowsSrwLock(lock_address);
    try testing.expectEqual(@as(u64, 6), state.windows_srw_locks[state.windowsSrwLockIndex(lock_address).?].owner_thread_id);
}

test "the frame's threads ask for performance cores and the pollers give them up" {
    try testing.expectEqual(ElfState.HostQos.user_interactive, ElfState.hostQosForGuestThread("MAIN_THREAD (F8000014)"));
    try testing.expectEqual(ElfState.HostQos.user_interactive, ElfState.hostQosForGuestThread("RENDER (F800010C)"));
    try testing.expectEqual(ElfState.HostQos.user_interactive, ElfState.hostQosForGuestThread("GPU Commands (0100000C)"));
    try testing.expectEqual(ElfState.HostQos.utility, ElfState.hostQosForGuestThread("xe::threading::TimerQueue"));
    try testing.expectEqual(ElfState.HostQos.utility, ElfState.hostQosForGuestThread("Logging Writer"));
    // Audio and everything unnamed keep the default.
    try testing.expectEqual(ElfState.HostQos.default, ElfState.hostQosForGuestThread("XMA Decoder (01000014)"));
    try testing.expectEqual(ElfState.HostQos.default, ElfState.hostQosForGuestThread("AUDIO (F8000110)"));
    try testing.expectEqual(ElfState.HostQos.default, ElfState.hostQosForGuestThread(""));
}

test "a back-off at depth two lends Xenia's global mutex to its waiter and restores the depth when it is handed back" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.setParallelGuestExecution(true);
    defer state.setParallelGuestExecution(false);
    const mutex = MEM_BASE + 0x3000;
    state.xenia_global_mutex_address = mutex;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };

    // Thread 5 holds the mutex at depth two: an outer frame (Xenia's
    // KeInsertQueueDpc) and the wait loop inside it.
    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(mutex));
    state.write32(mutex + XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 5);
    state.write32(mutex + XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 2);
    // A back-off with nobody waiting lends nothing.
    try testing.expect(!state.yieldXeniaGlobalMutexForBackoff());
    try testing.expectEqual(@as(u64, 0), state.xenia_global_mutex_lends);

    // Thread 6 - the one compiling the function thread 5 waits for - queues.
    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(mutex));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(mutex));

    // Thread 5 backs off: the lock goes to thread 6, and thread 5 queues
    // behind it with its depth saved and the call left unanswered.
    state.windows_active_guest_thread_slot = 0;
    try testing.expect(state.yieldXeniaGlobalMutexForBackoff());
    const lock_index = state.windowsSrwLockIndex(mutex).?;
    try testing.expectEqual(@as(u64, 6), state.windows_srw_locks[lock_index].owner_thread_id);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[1].status);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[0].status);
    try testing.expectEqual(mutex, state.windows_guest_threads[0].blocked_srw_lock);
    try testing.expectEqual(@as(u32, 0), state.read32(mutex + XENIA_GLOBAL_MUTEX_OWNER_OFFSET));
    try testing.expectEqual(@as(u32, 0), state.read32(mutex + XENIA_GLOBAL_MUTEX_RECURSION_OFFSET));
    try testing.expectEqual(XeniaGlobalLend{ .owner = 5, .recursion = 2 }, state.windows_guest_threads[0].xenia_global_lend.?);
    try testing.expectEqual(@as(u64, 1), state.xenia_global_mutex_lends);

    // Thread 6 collects the handoff, does its work at depth one and unlocks
    // the way xe_global_mutex does, which hands the lock back to thread 5.
    state.windows_active_guest_thread_slot = 1;
    state.windows_guest_threads[1].status = .running;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(mutex));
    state.write32(mutex + XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 6);
    state.write32(mutex + XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 1);
    state.write32(mutex + XENIA_GLOBAL_MUTEX_RECURSION_OFFSET, 0);
    state.write32(mutex + XENIA_GLOBAL_MUTEX_OWNER_OFFSET, 0);
    state.releaseWindowsSrwLock(mutex);
    try testing.expectEqual(@as(u64, 5), state.windows_srw_locks[lock_index].owner_thread_id);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);

    // Thread 5 retries its back-off: it takes the lock back at the depth it
    // lent, and the call proceeds as an ordinary back-off.
    state.windows_active_guest_thread_slot = 0;
    state.windows_guest_threads[0].status = .running;
    try testing.expect(!state.yieldXeniaGlobalMutexForBackoff());
    try testing.expectEqual(@as(u32, 5), state.read32(mutex + XENIA_GLOBAL_MUTEX_OWNER_OFFSET));
    try testing.expectEqual(@as(u32, 2), state.read32(mutex + XENIA_GLOBAL_MUTEX_RECURSION_OFFSET));
    try testing.expectEqual(@as(?XeniaGlobalLend, null), state.windows_guest_threads[0].xenia_global_lend);
    try testing.expectEqual(@as(u64, 1), state.xenia_global_mutex_lend_returns);
    try testing.expectEqual(@as(u64, 5), state.windows_srw_locks[lock_index].owner_thread_id);
}

test "SRW acquire and release publish the TSO store buffer around ownership transfer" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const lock_address = MEM_BASE + 0x2200;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    var published: [4]u8 align(4) = [_]u8{0} ** 4;
    var queue: tso_memory.StoreBuffer = .{};
    const previous_queue = tso_memory.setActiveStoreBuffer(&queue);
    defer _ = tso_memory.setActiveStoreBuffer(previous_queue);

    // Acquire is an acquire boundary: following code must not observe stale
    // state after it takes ownership.
    tso_memory.store(u32, published[0..], 0xA1B2_C3D4);
    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));
    try testing.expectEqual(@as(usize, 0), queue.pendingCount());
    try testing.expectEqual(@as(u32, 0xA1B2_C3D4), std.mem.readInt(u32, published[0..], .little));

    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(lock_address));

    // Release publishes the protected data before it grants the lock to the
    // waiter, which retries at the original import call site.
    tso_memory.store(u32, published[0..], 0xD4C3_B2A1);
    state.windows_active_guest_thread_slot = 0;
    state.releaseWindowsSrwLock(lock_address);
    try testing.expectEqual(@as(usize, 0), queue.pendingCount());
    try testing.expectEqual(@as(u32, 0xD4C3_B2A1), std.mem.readInt(u32, published[0..], .little));
    try testing.expectEqual(@as(u64, 6), state.windows_srw_locks[state.windowsSrwLockIndex(lock_address).?].owner_thread_id);
}

test "the owner context queues for an SRW lock and is not starved by workers" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const lock_address = MEM_BASE + 0x2100;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };

    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));

    state.windows_active_guest_thread_slot = null;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    state.noteWindowsOwnerSrwWait(lock_address);

    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(lock_address));

    state.windows_active_guest_thread_slot = 0;
    state.releaseWindowsSrwLock(lock_address);
    // The owner queued first, so it gets the lock and the worker keeps waiting.
    try testing.expectEqual(@as(u64, 1), state.windows_srw_locks[state.windowsSrwLockIndex(lock_address).?].owner_thread_id);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);
    state.windows_active_guest_thread_slot = null;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.acquireWindowsSrwLock(lock_address));
    try testing.expect(!state.windows_srw_locks[state.windowsSrwLockIndex(lock_address).?].owner_waiting);
}

test "a critical section excludes other threads, nests for its owner, and goes to its longest waiter" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const section = MEM_BASE + 0x2400;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    state.windows_guest_threads[2] = .{ .status = .running, .handle = 0x12, .thread_id = 7 };
    state.initializeWindowsCriticalSection(section);
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(section + 8));

    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    try testing.expectEqual(@as(u32, 2), state.read32(section + 12));
    try testing.expectEqual(@as(u64, 5), state.read64(section + 16));

    // Thread 7 queues first, thread 6 second; neither gets in, TryEnter
    // included - every Enter used to succeed.
    state.windows_active_guest_thread_slot = 2;
    try testing.expect(!state.tryEnterWindowsCriticalSection(section));
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.enterWindowsCriticalSection(section));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(section));
    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.enterWindowsCriticalSection(section));
    try testing.expect(state.blockWindowsGuestThreadOnSrwLock(section));

    // The first leave only unwinds the recursion.
    state.windows_active_guest_thread_slot = 0;
    state.leaveWindowsCriticalSection(section);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[2].status);
    state.leaveWindowsCriticalSection(section);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[2].status);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);
    try testing.expectEqual(@as(u64, 7), state.read64(section + 16));
    // The thread that let it go cannot take it back ahead of the waiter.
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.contended, state.enterWindowsCriticalSection(section));

    state.windows_active_guest_thread_slot = 2;
    state.windows_guest_threads[2].status = .running;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    try testing.expectEqual(@as(u32, 1), state.read32(section + 12));
    state.leaveWindowsCriticalSection(section);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[1].status);
    state.windows_active_guest_thread_slot = 1;
    state.windows_guest_threads[1].status = .running;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    state.leaveWindowsCriticalSection(section);
    // Free and uncontended: no record left behind.
    try testing.expect(state.windowsCriticalSectionIndex(section) == null);
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(section + 8));
    try testing.expectEqual(@as(u64, 2), state.windows_critical_section_handoffs);
    // A leave without an enter is counted, not obeyed.
    state.leaveWindowsCriticalSection(section);
    try testing.expectEqual(@as(u64, 1), state.windows_critical_section_release_mismatches);
}

/// One XThread's side of an Xbox kernel call, laid out the way Xenia's
/// export trampolines read it: a PPCContext whose r3/r4 carry the arguments,
/// whose +0xA98 is the virtual membase and whose r13 is the PCR.
const XboxCallFixture = struct {
    context: u64,
    membase: u64,
    stack: u64,
    return_rip: u64,

    const trampoline: u64 = 0x1409_986D0;

    fn init(state: *ElfState, context_offset: u64, pcr: u32, kthread: u32) XboxCallFixture {
        const fixture: XboxCallFixture = .{
            .context = state.mem_base + context_offset,
            .membase = state.mem_base + 0x40000,
            .stack = state.mem_base + context_offset + 0x1000,
            .return_rip = state.mem_base + 0x1000,
        };
        state.write64(fixture.context + PPC_CONTEXT_VIRTUAL_MEMBASE, fixture.membase);
        state.write64(fixture.context + ppcContextGpr(13), pcr);
        state.write32(fixture.membase + pcr + xbox_critical_section.pcr_current_thread, @byteSwap(kthread));
        return fixture;
    }

    /// Stand at the trampoline's first instruction, as Xenia's
    /// GuestToHostThunk leaves a thread after `call rax`.
    fn arrive(self: XboxCallFixture, state: *ElfState, section: u32, argument: u32) void {
        state.write64(self.context + ppcContextGpr(3), section);
        state.write64(self.context + ppcContextGpr(4), argument);
        state.write64(self.stack, self.return_rip);
        state.regs = .{ .rcx = self.context, .rsp = self.stack, .rip = trampoline };
    }

    fn returned(self: XboxCallFixture, state: *const ElfState) bool {
        return state.regs.rip == self.return_rip and state.regs.rsp == self.stack + 8;
    }

    fn r3(self: XboxCallFixture, state: *const ElfState) u64 {
        return state.read64(self.context + ppcContextGpr(3));
    }
};

test "Xbox Rtl trampolines read the section from the PPCContext and answer in r3" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_active_guest_thread_slot = 0;
    const kthread: u32 = 0x7000_0100;
    const caller = XboxCallFixture.init(&state, 0x10000, 0x3000, kthread);
    const guest: u32 = 0x2400;
    const section = caller.membase + guest;
    // Bytes 0x00-0x27 of the PPCContext precede r0 and are Xenia's; the
    // bridge that read `rcx` as the section wrote its header and lock there.
    state.write64(caller.context + 0x10, 0x1122_3344_5566_7788);
    state.write64(caller.context + 0x18, 0x99AA_BBCC_DDEE_FF00);

    caller.arrive(&state, guest, 4000);
    try testing.expect(state.handleXboxCriticalSectionExport(.initialize_and_spin_count));
    try testing.expect(caller.returned(&state));
    try testing.expectEqual(@as(u64, 0), caller.r3(&state)); // X_STATUS_SUCCESS in r3
    try testing.expectEqual(@as(u8, 1), state.read8(section)); // EventSynchronizationObject
    try testing.expectEqual(@as(u8, 16), state.read8(section + 1)); // spin count / 256
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(section + 16));
    try testing.expectEqual(@as(u64, 0x1122_3344_5566_7788), state.read64(caller.context + 0x10));
    try testing.expectEqual(@as(u64, 0x99AA_BBCC_DDEE_FF00), state.read64(caller.context + 0x18));

    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));
    try testing.expect(caller.returned(&state));
    try testing.expectEqual(kthread, @byteSwap(state.read32(section + 24))); // the caller's KTHREAD, as Xenia writes it
    try testing.expectEqual(@as(u32, 1), @byteSwap(state.read32(section + 20)));
    try testing.expectEqual(@as(u32, 0), state.read32(section + 16));

    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.try_enter));
    try testing.expectEqual(@as(u64, 1), caller.r3(&state));
    try testing.expectEqual(@as(u32, 2), @byteSwap(state.read32(section + 20)));
    try testing.expectEqual(@as(u32, 1), state.read32(section + 16));

    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    try testing.expect(caller.returned(&state));
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(section + 16));
    try testing.expectEqual(@as(u32, 0), state.read32(section + 24));

    // A null section is Xenia's logged no-op; TryEnter says it got it.
    caller.arrive(&state, 0, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.try_enter));
    try testing.expectEqual(@as(u64, 1), caller.r3(&state));
    caller.arrive(&state, 0, 0);
    try testing.expect(!state.handleXboxCriticalSectionExport(.initialize));

    const stats = &state.xbox_critical_section_stats;
    try testing.expectEqual(@as(u64, 1), stats.acquired);
    try testing.expectEqual(@as(u64, 0), stats.counted);
    try testing.expectEqual(@as(u64, 1), stats.null_sections);
    try testing.expectEqual(@as(u64, 0), stats.leave_mismatches);
    try testing.expectEqual(@as(u64, 0), stats.synthetic_owners);
    try testing.expectEqual(@as(u64, 1), state.xbox_critical_section_hooks.fallbacks[@intFromEnum(xbox_critical_section.Export.initialize)]);
}

test "a contended Xbox enter parks the worker and the release grants it the section" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    const holder = XboxCallFixture.init(&state, 0x10000, 0x3000, 0x7000_0100);
    const waiter = XboxCallFixture.init(&state, 0x14000, 0x3400, 0x7000_0200);
    const guest: u32 = 0x2400;
    const section = holder.membase + guest;

    state.windows_active_guest_thread_slot = 0;
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.initialize));
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));

    state.windows_active_guest_thread_slot = 1;
    waiter.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));
    // Parked at the trampoline, counted into lock_count, on no host event.
    try testing.expectEqual(XboxCallFixture.trampoline, state.regs.rip);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);
    try testing.expectEqual(section, state.windows_guest_threads[1].blocked_srw_lock);
    try testing.expectEqual(section, state.windows_guest_threads[1].xbox_cs_wait);
    try testing.expectEqual(@as(u32, 1), state.read32(section + 16));

    state.windows_active_guest_thread_slot = 0;
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[1].status);
    try testing.expect(state.windows_guest_threads[1].xbox_cs_granted);
    // Handed over, not free: the holder cannot take it back first.
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.try_enter));
    try testing.expectEqual(@as(u64, 0), holder.r3(&state));

    // The waiter's call runs again and collects the grant without counting
    // itself a second time.
    state.windows_active_guest_thread_slot = 1;
    state.windows_guest_threads[1].status = .running;
    waiter.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));
    try testing.expect(waiter.returned(&state));
    try testing.expectEqual(@as(u32, 0x7000_0200), @byteSwap(state.read32(section + 24)));
    try testing.expectEqual(@as(u32, 1), @byteSwap(state.read32(section + 20)));
    try testing.expectEqual(@as(u32, 0), state.read32(section + 16));
    try testing.expectEqual(@as(u64, 0), state.windows_guest_threads[1].xbox_cs_wait);

    waiter.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(section + 16));
    const stats = &state.xbox_critical_section_stats;
    try testing.expectEqual(@as(u64, 1), stats.counted);
    try testing.expectEqual(@as(u64, 1), stats.parks);
    try testing.expectEqual(@as(u64, 1), stats.grants);
    try testing.expectEqual(@as(u64, 0), stats.signals);
    try testing.expectEqual(@as(u64, 1), stats.try_failures);
}

test "a release before the waiter parks leaves the embedded event set for it" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };
    const holder = XboxCallFixture.init(&state, 0x10000, 0x3000, 0x7000_0100);
    const waiter = XboxCallFixture.init(&state, 0x14000, 0x3400, 0x7000_0200);
    const guest: u32 = 0x2400;
    const section = holder.membase + guest;
    const access: ElfState.XboxSectionAccess = .{ .state = &state, .section = section };

    state.windows_active_guest_thread_slot = 0;
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.initialize));
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));

    // The waiter counts itself, then loses the race to the release before
    // it reaches the scheduler.
    try testing.expectEqual(xbox_critical_section.Entry.counted, xbox_critical_section.enter(access, 0x7000_0200));
    holder.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    try testing.expectEqual(@as(u32, 1), @byteSwap(state.read32(section + 4))); // the event holds the wake

    state.windows_active_guest_thread_slot = 1;
    waiter.arrive(&state, guest, 0);
    const call = state.decodeXboxCriticalSectionCall().?;
    try testing.expectEqual(section, call.section);
    try testing.expectEqual(ElfState.XboxWait.acquired, state.awaitXboxCriticalSection(call, 0x7000_0200));
    try testing.expectEqual(WindowsGuestThreadStatus.running, state.windows_guest_threads[1].status);
    try testing.expectEqual(@as(u32, 0), state.read32(section + 4));
    try testing.expectEqual(@as(u32, 0x7000_0200), @byteSwap(state.read32(section + 24)));
    try testing.expectEqual(@as(u64, 1), state.xbox_critical_section_stats.signals);
    try testing.expectEqual(@as(u64, 1), state.xbox_critical_section_stats.signals_consumed);
}

test "an Xbox critical-section wait provenance line is kept once per parked event" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const event: u64 = 0xFFFF_F000_0000_01DB;
    state.registerWindowsEvent(event, false, false);
    const thread = &state.windows_guest_threads[13];
    thread.* = .{
        .status = .blocked,
        .handle = 0xFFFF_F000_0000_01CD,
        .critical_section = 0x2400,
        .critical_section_membase = state.mem_base,
        .blocked_wait_handle = event,
        .blocked_wait_timeout = std.math.maxInt(u32),
    };
    const import_name = "NtWaitForSingleObject";
    @memcpy(thread.last_import[0..import_name.len], import_name);
    thread.last_import_len = @intCast(import_name.len);

    state.noteXboxCriticalSectionWaitProvenance(thread, event, std.math.maxInt(u32));
    try testing.expectEqual(event, thread.xbox_cs_wait_provenance_handle);
    // A repeated park on the same auto-reset object does not flood the log.
    state.noteXboxCriticalSectionWaitProvenance(thread, event, std.math.maxInt(u32));
    try testing.expectEqual(event, thread.xbox_cs_wait_provenance_handle);
    // Nothing resumes it: only a real release may.
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
}

test "Xbox critical-section leave publishes protected stores before returning" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_active_guest_thread_slot = 0;
    const caller = XboxCallFixture.init(&state, 0x10000, 0x3000, 0x7000_0100);
    const guest: u32 = 0x2400;
    const protected_data = state.mem_base + 0x3000;
    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.initialize));
    caller.arrive(&state, guest, 0);
    try testing.expect(state.handleXboxCriticalSectionExport(.enter));

    var buffer: tso_memory.StoreBuffer = .{};
    const prior_buffer = tso_memory.setActiveStoreBuffer(&buffer);
    defer _ = tso_memory.setActiveStoreBuffer(prior_buffer);
    state.write32(protected_data, 0xC0DE_CAFE);
    try testing.expect(buffer.pendingCount() != 0);
    caller.arrive(&state, guest, 0);

    try testing.expect(state.handleXboxCriticalSectionExport(.leave));
    try testing.expect(buffer.isEmpty());
    try testing.expectEqual(@as(u32, 0xC0DE_CAFE), state.read32(protected_data));
    try testing.expect(caller.returned(&state));
    try testing.expectEqual(@as(u32, 0xFFFF_FFFF), state.read32(caller.membase + guest + 16));
}

test "EnterCriticalSection parks a contending worker at its call site and resumes it holding the section" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const section = state.mem_base + 0x2400;
    const call_site = state.mem_base + 0x3000;
    const return_rip = state.mem_base + 0x1000;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };

    state.windows_active_guest_thread_slot = 0;
    state.regs = .{ .rcx = section, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "EnterCriticalSection", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);

    state.windows_active_guest_thread_slot = 1;
    state.regs = .{ .rcx = section, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "EnterCriticalSection", return_rip));
    // Not completed: the worker is parked at the call.
    try testing.expectEqual(call_site, state.regs.rip);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[1].status);

    state.windows_active_guest_thread_slot = 0;
    state.regs = .{ .rcx = section, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "LeaveCriticalSection", return_rip));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[1].status);

    state.windows_active_guest_thread_slot = 1;
    state.windows_guest_threads[1].status = .running;
    state.regs = .{ .rcx = section, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "EnterCriticalSection", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u64, 6), state.read64(section + 16));
}

test "SleepConditionVariableCS releases its section, sleeps until woken, and returns holding it again" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const section = state.mem_base + 0x2400;
    const condition = state.mem_base + 0x2500;
    const call_site = state.mem_base + 0x3000;
    const return_rip = state.mem_base + 0x1000;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };

    state.windows_active_guest_thread_slot = 0;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    state.regs = .{ .rcx = condition, .rdx = section, .r8 = 0xFFFF_FFFF, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepConditionVariableCS", return_rip));
    try testing.expectEqual(call_site, state.regs.rip);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[0].status);

    // The section was released for the wait: the signalling thread gets in.
    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsSrwAcquireResult.acquired, state.enterWindowsCriticalSection(section));
    state.regs = .{ .rcx = condition, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "WakeConditionVariable", return_rip));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    // Woken while the signaller still holds the section: the waiter's retry
    // parks on the section, not returns.
    state.windows_active_guest_thread_slot = 0;
    state.windows_guest_threads[0].status = .running;
    state.regs = .{ .rcx = condition, .rdx = section, .r8 = 0xFFFF_FFFF, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepConditionVariableCS", return_rip));
    try testing.expectEqual(call_site, state.regs.rip);
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[0].status);
    state.windows_active_guest_thread_slot = 1;
    state.leaveWindowsCriticalSection(section);
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);

    state.windows_active_guest_thread_slot = 0;
    state.windows_guest_threads[0].status = .running;
    state.regs = .{ .rcx = condition, .rdx = section, .r8 = 0xFFFF_FFFF, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepConditionVariableCS", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u64, 1), state.regs.rax);
    try testing.expectEqual(@as(u64, 5), state.read64(section + 16));
    try testing.expectEqual(@as(u64, 1), state.windows_native_condition_resumes);

    // A timed wait that runs out returns FALSE/ERROR_TIMEOUT with the
    // section held again.
    state.regs = .{ .rcx = condition, .rdx = section, .r8 = 5, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepConditionVariableCS", return_rip));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, state.windows_guest_threads[0].status);
    // Let the guest clock move, then put the deadline at "now".
    state.refreshWindowsGuestClock();
    sleepForTest(2);
    state.refreshWindowsGuestClock();
    state.windows_guest_threads[0].blocked_wait_deadline = @max(state.windowsGuestClockTicks(), 1);
    _ = state.wakeExpiredWindowsGuestWaits();
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    state.windows_guest_threads[0].status = .running;
    state.regs = .{ .rcx = condition, .rdx = section, .r8 = 5, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "SleepConditionVariableCS", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(@as(u32, 1460), state.windows_last_error);
    try testing.expectEqual(@as(u64, 5), state.read64(section + 16));
}

test "an InitOnce another thread is running makes the caller wait for its completion" {
    var state = ElfState.initWithMemory(testing.allocator, 0x80000);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const once = state.mem_base + 0x2600;
    const pending = state.mem_base + 0x2610;
    const context = state.mem_base + 0x2618;
    const call_site = state.mem_base + 0x3000;
    const return_rip = state.mem_base + 0x1000;
    state.windows_guest_threads[0] = .{ .status = .running, .handle = 0x10, .thread_id = 5 };
    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0x11, .thread_id = 6 };

    state.windows_active_guest_thread_slot = 0;
    state.regs = .{ .rcx = once, .rdx = 0, .r8 = pending, .r9 = context, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "InitOnceBeginInitialize", return_rip));
    try testing.expectEqual(@as(u32, 1), state.read32(pending));

    // A second thread arrives while the first initializes: it waits at the
    // call instead of being told the object is ready.
    state.windows_active_guest_thread_slot = 1;
    state.regs = .{ .rcx = once, .rdx = 0, .r8 = pending, .r9 = context, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "InitOnceBeginInitialize", return_rip));
    try testing.expectEqual(call_site, state.regs.rip);

    state.windows_active_guest_thread_slot = 0;
    state.regs = .{ .rcx = once, .rdx = 0, .r8 = 0x5000, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "InitOnceComplete", return_rip));

    state.windows_active_guest_thread_slot = 1;
    state.regs = .{ .rcx = once, .rdx = 0, .r8 = pending, .r9 = context, .rip = call_site };
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "KERNEL32.dll", "InitOnceBeginInitialize", return_rip));
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u32, 0), state.read32(pending));
    try testing.expectEqual(@as(u64, 0x5000), state.read64(context));
}

test "a semaphore release gives its count to the waiter it wakes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const handle: u64 = 0xfffff0000000021f;
    state.registerWindowsSemaphore(handle, 0, 2);
    state.windows_guest_threads[0] = .{ .status = .blocked, .handle = 0x30, .thread_id = 9, .blocked_wait_handle = handle };
    try testing.expect(state.releaseWindowsSemaphore(handle, 1));
    try testing.expectEqual(WindowsGuestThreadStatus.runnable, state.windows_guest_threads[0].status);
    // The woken waiter took the count; a second caller does not get one too.
    try testing.expectEqual(@as(u32, 0), state.windowsWaitObjectSemaphoreCount(handle).?);
    try testing.expect(!state.releaseWindowsSemaphore(0xdead, 1));
}

fn setUpGuestAccessViolation(state: *ElfState) struct { page: u64, stack: u64, handler: u64 } {
    const page = MEM_BASE + 0x30000;
    const stack = MEM_BASE + 0x60000;
    const handler = MEM_BASE + 0x1234;
    state.noteGuestPageProtection(page, 0x1000, 0x01, "VirtualAlloc", 0);
    state.windows_vectored_exception_handler = handler;
    state.regs.rsp = stack;
    return .{ .page = page, .stack = stack, .handler = handler };
}

test "guest thread snapshots preserve faults translator and callback continuations" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_access_violation_pending = true;
    state.guest_access_violation = .{ .address = MEM_BASE + 0x31000, .instruction_rip = MEM_BASE + 0x5200, .width = 8, .is_write = true };
    state.windows_initterm_frames[0] = .{
        .begin = MEM_BASE + 0x1000,
        .end = MEM_BASE + 0x1080,
        .return_rip = MEM_BASE + 0x5200,
        .return_is_direct = true,
        .returns_error = false,
        .callback_count = 3,
    };
    state.windows_initterm_frame_count = 1;
    state.windows_qsort_frames[0] = .{ .base = MEM_BASE + 0x2000, .nmemb = 7, .element_size = 16, .i = 4, .j = 2 };
    state.windows_qsort_frame_count = 1;
    state.windows_message_dispatch_frames[0] = .{ .return_rip = MEM_BASE + 0x6100, .return_rsp = MEM_BASE + 0x7200, .return_is_direct = true };
    state.windows_message_dispatch_frame_count = 1;
    state.windows_audio_callback_frames[0] = .{ .return_rip = MEM_BASE + 0x6300, .return_rsp = MEM_BASE + 0x7300, .return_is_direct = false };
    state.windows_audio_callback_frame_count = 1;
    state.block_jit_scratch.abort = 1;
    state.block_jit_scratch.index = 7;
    state.step_retired = 19;
    state.windows_current_import = "owner-import";
    state.windows_thread_id = 71;

    const context = state.captureWindowsGuestContext();
    state.guest_access_violation_pending = false;
    state.guest_access_violation = .{};
    state.windows_initterm_frame_count = 0;
    state.windows_qsort_frame_count = 0;
    state.windows_message_dispatch_frame_count = 0;
    state.windows_audio_callback_frame_count = 0;
    state.block_jit_scratch = .{};
    state.step_retired = 1;
    state.windows_current_import = "worker-import";
    state.windows_thread_id = 2;
    state.restoreWindowsGuestContext(&context);

    try testing.expect(state.guest_access_violation_pending);
    try testing.expectEqual(MEM_BASE + 0x31000, state.guest_access_violation.address);
    try testing.expectEqual(@as(u32, 7), state.block_jit_scratch.index);
    try testing.expectEqual(@as(u8, 1), state.block_jit_scratch.abort);
    try testing.expectEqual(@as(u32, 19), state.step_retired);
    try testing.expectEqualStrings("owner-import", state.windows_current_import);
    try testing.expectEqual(@as(u64, 71), state.currentWindowsThreadId());
    try testing.expectEqual(@as(usize, 1), state.windows_initterm_frame_count);
    try testing.expectEqual(MEM_BASE + 0x1000, state.windows_initterm_frames[0].begin);
    try testing.expectEqual(@as(u64, 3), state.windows_initterm_frames[0].callback_count);
    try testing.expectEqual(@as(usize, 1), state.windows_qsort_frame_count);
    try testing.expectEqual(@as(u64, 4), state.windows_qsort_frames[0].i);
    try testing.expectEqual(@as(usize, 1), state.windows_message_dispatch_frame_count);
    try testing.expectEqual(MEM_BASE + 0x6100, state.windows_message_dispatch_frames[0].return_rip);
    try testing.expectEqual(@as(usize, 1), state.windows_audio_callback_frame_count);
    try testing.expectEqual(MEM_BASE + 0x6300, state.windows_audio_callback_frames[0].return_rip);

    state.windows_guest_threads[0].thread_id = 17;
    state.windows_active_guest_thread_slot = 0;
    const worker_context = state.captureWindowsGuestContext();
    state.windows_active_guest_thread_slot = null;
    state.windows_thread_id = 1;
    state.restoreWindowsGuestContext(&worker_context);
    try testing.expectEqual(@as(u64, 17), state.currentWindowsThreadId());
}

test "guest call tracing keeps a separate stack for each Windows worker" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.trace_calls = true;

    state.windows_active_guest_thread_slot = 0;
    state.noteGuestCall(.direct, MEM_BASE + 0x1000, MEM_BASE + 0x2000);
    try testing.expectEqual(@as(usize, 1), state.windows_guest_threads[0].call_stack.frames.items.len);
    try testing.expectEqual(@as(usize, 0), state.call_stack.frames.items.len);

    state.windows_active_guest_thread_slot = 1;
    state.noteGuestCall(.indirect, MEM_BASE + 0x3000, MEM_BASE + 0x4000);
    try testing.expectEqual(@as(usize, 1), state.windows_guest_threads[1].call_stack.frames.items.len);
    try testing.expectEqual(@as(usize, 1), state.windows_guest_threads[0].call_stack.frames.items.len);

    state.windows_active_guest_thread_slot = 0;
    state.noteGuestReturn(MEM_BASE + 0x2000);
    try testing.expectEqual(@as(usize, 0), state.windows_guest_threads[0].call_stack.frames.items.len);
    try testing.expectEqual(@as(usize, 1), state.windows_guest_threads[1].call_stack.frames.items.len);
}

test "a store to a no-access page is withheld and raised through the vectored handler" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const setup = setUpGuestAccessViolation(&state);
    try testing.expect(state.guest_page_protection.isActive());
    try testing.expect(state.guestMemory(setup.stack - 0x800, 0x800) != null);

    state.last_instruction_rip = MEM_BASE + 0x5000;
    state.regs.rip = MEM_BASE + 0x5003; // the store has "executed"
    state.regs.rax = 0x1234_5678;
    state.write32(setup.page + 0x714, 0);
    state.writeMemVal(setup.page + 0x714, .bits32, 0xCAFE);
    // Withheld: a register write must reach the device, not plain memory.
    try testing.expectEqual(@as(u32, 0), state.read32(setup.page + 0x714));
    try testing.expect(state.guest_access_violation_pending);

    state.raiseGuestAccessViolation();
    try testing.expect(!state.guest_access_violation_pending);
    try testing.expectEqual(setup.handler, state.regs.rip);
    try testing.expectEqual(SYNTHETIC_WINDOWS_EXCEPTION_RETURN, state.read64(state.regs.rsp));
    // Entry stack alignment: 8 modulo 16, as after any call.
    try testing.expectEqual(@as(u64, 8), state.regs.rsp % 16);
    const pointers = state.regs.rcx;
    const record = state.read64(pointers);
    const context = state.read64(pointers + 8);
    try testing.expectEqual(@as(u32, 0xC000_0005), state.read32(record));
    try testing.expectEqual(@as(u64, 1), state.read64(record + 32)); // write
    try testing.expectEqual(setup.page + 0x714, state.read64(record + 40));
    try testing.expectEqual(MEM_BASE + 0x5000, state.read64(context + 0xf8)); // faulting instruction
    try testing.expectEqual(@as(u64, 0x1234_5678), state.read64(context + 0x78));
    try testing.expectEqual(@as(u64, 0), context % 16);

    // The handler decodes the store, delivers it, advances past it, and
    // returns EXCEPTION_CONTINUE_EXECUTION.
    state.write64(context + 0xf8, MEM_BASE + 0x5003);
    state.write64(context + 0x78, 0x55);
    state.regs.rax = 0xFFFF_FFFF;
    state.regs.rsp += 8;
    state.regs.rip = SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(MEM_BASE + 0x5003, state.regs.rip);
    try testing.expectEqual(@as(u64, 0x55), state.regs.rax);
    try testing.expectEqual(setup.stack, state.regs.rsp);
    try testing.expectEqual(@as(u64, 1), state.guest_access_violations_handled);
    // Still withheld: the handler owned the value.
    try testing.expectEqual(@as(u32, 0), state.read32(setup.page + 0x714));
}

test "a declined access violation performs the access Rosette always did" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const setup = setUpGuestAccessViolation(&state);
    state.last_instruction_rip = MEM_BASE + 0x5000;
    state.regs.rip = MEM_BASE + 0x5003;
    state.writeMemVal(setup.page + 0x10, .bits32, 0xBEEF);
    state.raiseGuestAccessViolation();
    state.regs.rax = 0; // EXCEPTION_CONTINUE_SEARCH
    state.regs.rsp += 8;
    state.regs.rip = SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(MEM_BASE + 0x5003, state.regs.rip);
    try testing.expectEqual(@as(u32, 0xBEEF), state.read32(setup.page + 0x10));
    try testing.expectEqual(@as(u64, 1), state.guest_access_violations_unhandled);
}

fn setUpWriteWatchRetry(state: *ElfState) struct { page: u64, context: u64 } {
    const page = MEM_BASE + 0x30000;
    // Xenia's GPU write watch: PAGE_READONLY, so a store faults and a load
    // does not. Read-only pages only exist at all since the ntdll protect
    // entry points became real.
    state.noteGuestPageProtection(page, 0x1000, 0x02, "NtProtectVirtualMemory", 0);
    state.windows_vectored_exception_handler = MEM_BASE + 0x1234;
    state.regs.rsp = MEM_BASE + 0x60000;
    state.last_instruction_rip = MEM_BASE + 0x5000;
    state.regs.rip = MEM_BASE + 0x5003;
    state.writeMemVal(page + 0x40, .bits32, 0xABCD);
    state.raiseGuestAccessViolation();
    const context = state.read64(state.regs.rcx + 8);
    // The handler returns EXCEPTION_CONTINUE_EXECUTION with rip left on the
    // faulting instruction: the write-watch protocol asks for a retry.
    state.regs.rax = 0xFFFF_FFFF;
    state.regs.rsp += 8;
    state.regs.rip = SYNTHETIC_WINDOWS_EXCEPTION_RETURN;
    return .{ .page = page, .context = context };
}

test "a write watch that the handler cleared retries the faulting instruction" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const setup = setUpWriteWatchRetry(&state);
    try testing.expectEqual(MEM_BASE + 0x5000, state.read64(setup.context + 0xf8));
    // The store was withheld, and `TriggerCallbacks` unprotected the page.
    try testing.expectEqual(@as(u32, 0), state.read32(setup.page + 0x40));
    state.clearGuestPageProtection(setup.page, 0x1000);
    try testing.expect(state.handleSyntheticRip());
    // Back on the store, which now lands on its own. Rosette must not have
    // performed it: that would write it twice.
    try testing.expectEqual(MEM_BASE + 0x5000, state.regs.rip);
    try testing.expectEqual(@as(u32, 0), state.read32(setup.page + 0x40));
    try testing.expectEqual(@as(u64, 0), state.guest_access_violation_unresolved_retries);
    try testing.expectEqual(@as(u64, 1), state.guest_access_violations_handled);
}

test "a retry the handler did not resolve is performed once instead of looping forever" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const setup = setUpWriteWatchRetry(&state);
    // The protection is still on. Retrying would fault on the same
    // instruction forever, and a fault loop retires instructions, so no
    // liveness gate would ever call it a stall.
    try testing.expect(state.handleSyntheticRip());
    try testing.expectEqual(MEM_BASE + 0x5003, state.regs.rip);
    try testing.expectEqual(@as(u32, 0xABCD), state.read32(setup.page + 0x40));
    try testing.expectEqual(@as(u64, 1), state.guest_access_violation_unresolved_retries);
    try testing.expectEqual(@as(u64, 1), state.guest_access_violations_handled);
}

test "with no vectored handler the access completes at once and is counted" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const setup = setUpGuestAccessViolation(&state);
    state.windows_vectored_exception_handler = 0;
    state.regs.rip = MEM_BASE + 0x5003;
    state.writeMemVal(setup.page + 0x20, .bits16, 0x1122);
    state.raiseGuestAccessViolation();
    try testing.expectEqual(MEM_BASE + 0x5003, state.regs.rip);
    try testing.expectEqual(@as(u16, 0x1122), state.read16(setup.page + 0x20));
    try testing.expectEqual(@as(u64, 1), state.guest_access_violations_without_handler);
    // A read of a no-access page is noted and still returns the backing bytes.
    try testing.expectEqual(@as(u64, 0x1122), state.readMemVal(setup.page + 0x20, .bits16));
    try testing.expect(state.guest_access_violation_pending);
}

test "VirtualProtect's old protection is the one this run recorded" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const page = MEM_BASE + 0x40000;
    try testing.expectEqual(@as(u32, 0x40), state.guestPageProtectionFlags(page));
    state.noteGuestPageProtection(page, 0x1000, 0x02, "VirtualProtect", 0);
    try testing.expectEqual(@as(u32, 0x02), state.guestPageProtectionFlags(page));
    state.clearGuestPageProtection(page, 0x1000);
    try testing.expectEqual(@as(u32, 0x40), state.guestPageProtectionFlags(page));
    // A guard page is counted, not enforced as the wrong fault.
    state.noteGuestPageProtection(page, 0x1000, 0x104, "VirtualProtect", 0);
    try testing.expectEqual(@as(u64, 1), state.guest_page_protection_guard_requests);
    try testing.expect(!state.guest_page_protection.isActive());
}

test "NtProtectVirtualMemory is the ntdll spelling of VirtualProtect and arms the same watch" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = state.mem_base + 0x1000;
    const page = MEM_BASE + 0x40000;
    const base_slot = MEM_BASE + 0x50000;
    const size_slot = MEM_BASE + 0x50008;
    const old_slot = MEM_BASE + 0x50010;
    state.regs.rsp = MEM_BASE + 0x60000;

    // `xe::memory::Protect` passes the base and the length as in/out
    // parameters and always supplies a slot for the old protection.
    state.write64(base_slot, page + 0x40); // deliberately mid-page
    state.write64(size_slot, 0x40);
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF; // (HANDLE)-1, the current process
    state.regs.rdx = base_slot;
    state.regs.r8 = size_slot;
    state.regs.r9 = 0x02; // PAGE_READONLY, the write watch
    state.write64(state.regs.rsp + 32, old_slot);
    // Xenia's workers make this call while other guest threads run.
    state.parallel_guest_execution = true;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtProtectVirtualMemory", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax); // STATUS_SUCCESS
    // The kernel rounds the base down and the end up and writes both back.
    try testing.expectEqual(page, state.read64(base_slot));
    try testing.expectEqual(@as(u64, 0x1000), state.read64(size_slot));
    try testing.expectEqual(@as(u32, 0x40), state.read32(old_slot));
    try testing.expectEqual(@as(u32, 0x02), state.guestPageProtectionFlags(page));
    try testing.expectEqual(@as(u64, 1), state.guest_page_protection.stats().read_only_pages);
    // The point of the call: a store to the page now faults, and a read does
    // not. That is how Xenia learns a title rewrote a texture or a vertex
    // buffer, and it is what this name answering STATUS_SUCCESS and doing
    // nothing took away from every run before 2026-09-19.
    try testing.expect(state.guest_page_protection.faults(page + 0x10, 4, true));
    try testing.expect(!state.guest_page_protection.faults(page + 0x10, 4, false));

    // Unprotecting is the same call with PAGE_READWRITE, which is what
    // `PhysicalHeap::TriggerCallbacks` makes from inside the handler.
    state.write64(base_slot, page);
    state.write64(size_slot, 0x1000);
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = base_slot;
    state.regs.r8 = size_slot;
    state.regs.r9 = 0x04; // PAGE_READWRITE
    state.write64(state.regs.rsp + 32, old_slot);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtProtectVirtualMemory", return_rip));
    try testing.expectEqual(@as(u32, 0x02), state.read32(old_slot));
    try testing.expectEqual(@as(u64, 0), state.guest_page_protection.stats().read_only_pages);
    try testing.expect(!state.guest_page_protection.isActive());
}

test "NtProtectVirtualMemory refuses a call whose out-parameters it cannot reach" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = state.mem_base + 0x1000;
    state.regs.rsp = MEM_BASE + 0x60000;
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = 0; // no BaseAddress slot
    state.regs.r8 = MEM_BASE + 0x50008;
    state.regs.r9 = 0x02;
    state.write64(state.regs.rsp + 32, MEM_BASE + 0x50010);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtProtectVirtualMemory", return_rip));
    try testing.expectEqual(@as(u64, 0xC000_0005), state.regs.rax); // STATUS_ACCESS_VIOLATION
    try testing.expect(!state.guest_page_protection.isActive());
}

test "NtQueryVirtualMemory reports the protection this run recorded" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    const return_rip = state.mem_base + 0x1000;
    const page = MEM_BASE + 0x40000;
    const buffer = MEM_BASE + 0x50000;
    const result_slot = MEM_BASE + 0x50100;
    state.regs.rsp = MEM_BASE + 0x60000;
    state.noteGuestPageProtection(page, 0x3000, 0x02, "test", 0);

    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = page + 0x800;
    state.regs.r8 = 0; // MemoryBasicInformation
    state.regs.r9 = buffer;
    // Xenia hands its own region length here, not sizeof(the structure), so
    // the length is a lower bound and never an equality.
    state.write64(state.regs.rsp + 32, 0x1000);
    state.write64(state.regs.rsp + 40, result_slot);
    state.parallel_guest_execution = true;
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtQueryVirtualMemory", return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(page, state.read64(buffer + 0)); // BaseAddress
    try testing.expectEqual(@as(u32, 0x02), state.read32(buffer + 36)); // Protect
    // The region runs to the end of the pages that share that protection.
    try testing.expectEqual(@as(u64, 0x3000), state.read64(buffer + 24));
    try testing.expectEqual(@as(u64, 48), state.read64(result_slot));

    // An information class this runner does not model is refused rather than
    // answered with a zeroed structure.
    state.regs.rcx = 0xFFFF_FFFF_FFFF_FFFF;
    state.regs.rdx = page;
    state.regs.r8 = 2;
    state.regs.r9 = buffer;
    state.write64(state.regs.rsp + 32, 0x1000);
    state.write64(state.regs.rsp + 40, result_slot);
    try testing.expect(x64_linux_runtime.tryWindowsFunction(&state, "ntdll.dll", "NtQueryVirtualMemory", return_rip));
    try testing.expectEqual(@as(u64, 0xC000_0003), state.regs.rax);
}

test "a guest log line names the thread that wrote it" {
    try testing.expectEqualStrings("F8000014", ElfState.guestLogLineThreadToken("!> F8000014 ResolvePath() failed - device not found").?);
    try testing.expectEqualStrings("00000005", ElfState.guestLogLineThreadToken("w> 00000005 BaseHeap::AllocFixed").?);
    try testing.expectEqual(@as(?[]const u8, null), ElfState.guestLogLineThreadToken("!> short"));
    try testing.expectEqual(@as(?[]const u8, null), ElfState.guestLogLineThreadToken("no marker here"));
}

test "a signalled pthread condition waiter retakes its mutex through the image's own lock" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_pthread_cond_native = true;
    const wait_entry: u64 = MEM_BASE + 0x2000;
    const lock_entry: u64 = MEM_BASE + 0x2400;
    state.configureWindowsConditionEntries(wait_entry, null, null);
    state.configureWindowsMutexLockEntry(lock_entry);
    // A normal MinGW mutex (attributes 0), held by the waiter.
    const mutex = MEM_BASE + 0x3000;
    const record = MEM_BASE + 0x3100;
    state.write64(mutex, record);
    state.write32(record, 1);
    state.write32(record + 4, 0);
    state.write64(record + 8, 0xFFFF_F000_0000_0C01);
    const condition = MEM_BASE + 0x3200;
    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xD3, .thread_id = 5 };
    state.windows_active_guest_thread_slot = 3;
    const thread = &state.windows_guest_threads[3];

    // Entered by a tail jump: the caller's return address is at [rsp].
    const stack = MEM_BASE + 0x5000;
    const caller_return: u64 = MEM_BASE + 0x1234;
    state.regs.rsp = stack;
    state.write64(stack, caller_return);
    state.regs.rcx = condition;
    state.regs.rdx = mutex;
    try testing.expect(state.tryWindowsPthreadConditionShim(wait_entry, null));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
    try testing.expectEqual(@as(u32, 0), state.read32(record));

    // Signalled: instead of emulating the acquisition, the waiter calls
    // pthread_mutex_lock_intern(mutex, INFINITE) with the same return slot.
    try testing.expectEqual(@as(u64, 1), state.signalWindowsGuestCondition(condition, false));
    thread.status = .running;
    state.regs.rcx = condition;
    state.regs.rdx = mutex;
    try testing.expect(state.tryWindowsPthreadConditionShim(wait_entry, null));
    try testing.expectEqual(lock_entry, state.regs.rip);
    try testing.expectEqual(mutex, state.regs.rcx);
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF), state.regs.rdx);
    try testing.expectEqual(stack, state.regs.rsp);
    try testing.expectEqual(@as(u32, 0), state.read32(record));
    try testing.expectEqual(@as(u64, 1), state.windows_condition_relocks);

    // Entered by a call: the return address the call would have pushed is
    // pushed, so the lock returns to the call site.
    state.write32(record, 1);
    const call_return: u64 = MEM_BASE + 0x1005;
    state.regs.rcx = condition;
    state.regs.rdx = mutex;
    try testing.expect(state.tryWindowsPthreadConditionShim(wait_entry, call_return));
    try testing.expectEqual(@as(u64, 1), state.signalWindowsGuestCondition(condition, false));
    thread.status = .running;
    state.regs.rcx = condition;
    state.regs.rdx = mutex;
    try testing.expect(state.tryWindowsPthreadConditionShim(wait_entry, call_return));
    try testing.expectEqual(lock_entry, state.regs.rip);
    try testing.expectEqual(stack - 8, state.regs.rsp);
    try testing.expectEqual(call_return, state.read64(stack - 8));
}

test "a condition waiter that had to wait for its mutex retakes it with the waiters marker, as the image's lock does" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    // A MinGW mutex held by thread 7 (state 1), with its auto-reset event.
    const mutex = MEM_BASE + 0x3000;
    const record = MEM_BASE + 0x3100;
    state.write64(mutex, record);
    state.write32(record, 1);
    state.write32(record + 4, 0);
    state.write64(record + 8, 0xFFFF_F000_0000_0C01);
    state.write32(record + 0x10, 0);
    state.write32(record + 0x14, 7);
    const condition = MEM_BASE + 0x3200;

    // Thread 5 was signalled and now retakes the mutex: contended, so it
    // marks waiters (2) and parks on the event.
    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xD3, .thread_id = 5, .condition_resume = true, .blocked_condition_mutex = mutex };
    state.windows_active_guest_thread_slot = 3;
    const thread = &state.windows_guest_threads[3];
    try testing.expectEqual(ElfState.WindowsConditionWaitResult.blocked, state.waitWindowsGuestCondition(condition, mutex));
    try testing.expectEqual(@as(u32, 2), state.read32(record));
    try testing.expect(thread.condition_mutex_contended);

    // The holder unlocks the image's way (swap 0, SetEvent). Meanwhile a
    // second thread is parked in the image's own lock on the same event;
    // the waker must leave the marker so the next unlock wakes it too.
    state.write32(record, 0);
    thread.status = .running;
    try testing.expectEqual(ElfState.WindowsConditionWaitResult.resumed, state.waitWindowsGuestCondition(condition, mutex));
    try testing.expectEqual(@as(u32, 2), state.read32(record));
    try testing.expect(!thread.condition_mutex_contended);

    // A waiter that never had to wait takes a free mutex plainly, as the
    // image's first attempt does.
    state.write32(record, 0);
    thread.condition_resume = true;
    thread.blocked_condition_mutex = mutex;
    try testing.expectEqual(ElfState.WindowsConditionWaitResult.resumed, state.waitWindowsGuestCondition(condition, mutex));
    try testing.expectEqual(@as(u32, 1), state.read32(record));
}

test "a timed condition wait parks on the guest clock, and a signal or its deadline resumes it through its mutex" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_runtime_enabled = true;
    state.windows_pthread_cond_native = true;
    state.guest_clock.source = .retired_instructions;
    const timed_entry: u64 = MEM_BASE + 0x2000;
    state.configureWindowsTimedConditionEntry(timed_entry);

    // A MinGW mutex: pthread_mutex_t holds a pointer to its record, locked
    // (state 1) with default attributes and its own event handle.
    const mutex = MEM_BASE + 0x3000;
    const record = MEM_BASE + 0x3100;
    state.write64(mutex, record);
    state.write32(record, 1);
    state.write32(record + 4, 0);
    state.write64(record + 8, 0xFFFF_F000_0000_0C01);
    state.write32(record + 0x10, 0);
    state.write32(record + 0x14, 5);
    const condition = MEM_BASE + 0x3200;
    const timespec = MEM_BASE + 0x3300;

    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xD3, .thread_id = 5 };
    state.windows_active_guest_thread_slot = 3;
    const thread = &state.windows_guest_threads[3];
    const return_rip = MEM_BASE + 0x1005;

    // pthread_cond_timedwait_relative_np for 250 ms: the mutex is released
    // and the thread parks with a deadline on the guest clock.
    state.write64(timespec, 0);
    state.write32(timespec + 8, 250_000_000);
    state.guest_clock.ticks = 10_000;
    state.regs.rcx = condition;
    state.regs.rdx = mutex;
    state.regs.r8 = timespec;
    state.regs.r9 = 1;
    try testing.expect(state.tryWindowsPthreadConditionShim(timed_entry, return_rip));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
    try testing.expectEqual(@as(u32, 0), state.read32(record));
    try testing.expectEqual(10_000 + 250 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND, thread.blocked_wait_deadline);

    // A broadcast before the deadline: it returns zero with the mutex retaken.
    try testing.expectEqual(@as(u64, 1), state.signalWindowsGuestCondition(condition, true));
    thread.status = .running;
    state.regs.rax = 0xFFFF;
    try testing.expect(state.tryWindowsPthreadConditionShim(timed_entry, return_rip));
    try testing.expectEqual(@as(u64, 0), state.regs.rax);
    try testing.expectEqual(return_rip, state.regs.rip);
    try testing.expectEqual(@as(u32, 1), state.read32(record));

    // Again, and this time nobody signals before the deadline.
    try testing.expect(state.tryWindowsPthreadConditionShim(timed_entry, return_rip));
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
    state.windows_active_guest_thread_slot = null;
    state.guest_clock.ticks = thread.blocked_wait_deadline;
    try testing.expectEqual(@as(u64, 1), state.wakeExpiredWindowsGuestWaits());
    state.windows_active_guest_thread_slot = 3;
    thread.status = .running;
    try testing.expect(state.tryWindowsPthreadConditionShim(timed_entry, return_rip));
    try testing.expectEqual(WINDOWS_PTHREAD_ETIMEDOUT, state.regs.rax);
    try testing.expectEqual(@as(u32, 1), state.read32(record));
    try testing.expectEqual(@as(u64, 1), state.windows_condition_timeouts);

    // An absolute time already past: ETIMEDOUT at once, the mutex still held.
    state.write64(timespec, 1);
    state.write32(timespec + 8, 0);
    state.regs.r9 = 0;
    try testing.expect(state.tryWindowsPthreadConditionShim(timed_entry, return_rip));
    try testing.expectEqual(WINDOWS_PTHREAD_ETIMEDOUT, state.regs.rax);
    try testing.expectEqual(WindowsGuestThreadStatus.running, thread.status);
    try testing.expectEqual(@as(u32, 1), state.read32(record));
    try testing.expectEqual(@as(u64, 1), state.windows_condition_timed_immediate);
}

test "timed condition timeout detail is capped at the first ten expiries" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.windows_timed_wait_site_count = 1;
    state.windows_timed_wait_sites[0] = .{ .caller = MEM_BASE + 0x1000, .last_milliseconds = 500 };
    var thread: WindowsGuestThread = .{
        .handle = 0xD4,
        .thread_id = 6,
        .timed_wait_site = 1,
        .timed_wait_milliseconds = 500,
        .blocked_condition = MEM_BASE + 0x2000,
        .blocked_condition_mutex = MEM_BASE + 0x3000,
        .blocked_wait_deadline = 100,
    };

    for (0..WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT + 4) |_| {
        state.noteWindowsTimedConditionTimeout(&thread, 2, 101);
    }
    try testing.expectEqual(WINDOWS_TIMED_CONDITION_TIMEOUT_SAMPLE_LIMIT, state.windows_condition_timeout_samples);
}

test "an NT delay parks a worker to the guest-clock tick, and a zero delay yields" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    try testing.expect(!state.parkWindowsGuestDelayTicks(1_500));

    state.windows_guest_threads[2] = .{ .status = .running, .handle = 0xC2 };
    state.windows_active_guest_thread_slot = 2;
    try testing.expect(state.parkWindowsGuestDelayTicks(0));
    try testing.expect(state.windows_guest_slice_yield_requested);

    state.guest_clock.ticks = 40_000;
    try testing.expect(state.parkWindowsGuestDelayTicks(15 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND));
    const thread = &state.windows_guest_threads[2];
    try testing.expectEqual(WindowsGuestThreadStatus.blocked, thread.status);
    try testing.expectEqual(40_000 + 15 * WINDOWS_GUEST_CLOCK_TICKS_PER_MILLISECOND, thread.blocked_wait_deadline);
    try testing.expectEqual(@as(u64, 15), thread.blocked_wait_timeout);
    try testing.expectEqual(@as(u64, 1), state.windows_nt_delay_parks);
}

test "a closed wait object frees its slot, unless a parked thread still waits on it" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const kept: u64 = 0xFFFF_F000_0000_0D01;
    const freed: u64 = 0xFFFF_F000_0000_0D02;
    state.registerWindowsEvent(kept, false, false);
    state.registerWindowsEvent(freed, true, true);
    try testing.expectEqual(@as(usize, 2), state.windows_wait_object_high_water);

    state.windows_guest_threads[1] = .{ .status = .running, .handle = 0xC1 };
    state.windows_active_guest_thread_slot = 1;
    try testing.expectEqual(ElfState.WindowsWaitResult.blocked, state.waitWindowsGuestObject(kept, std.math.maxInt(u32)));
    state.windows_active_guest_thread_slot = null;

    try testing.expect(state.closeWindowsWaitObject(kept));
    try testing.expectEqual(@as(?bool, false), state.windowsWaitObjectReady(kept));
    try testing.expect(state.closeWindowsWaitObject(freed));
    try testing.expectEqual(@as(?bool, null), state.windowsWaitObjectReady(freed));
    try testing.expectEqual(@as(u64, 1), state.windows_wait_objects_freed);
    try testing.expectEqual(@as(usize, 1), state.windows_wait_object_high_water);
    // Not a wait object: the caller's other close paths decide what it was.
    try testing.expect(!state.closeWindowsWaitObject(0xFFFF_F000_0000_0DFF));

    // The next object takes the freed slot.
    state.registerWindowsSemaphore(0xFFFF_F000_0000_0D03, 1, 1);
    try testing.expectEqual(@as(usize, 2), state.windows_wait_object_high_water);
}

test "a full thread table gives the earliest finished thread's slot to a new thread, and its handle stays signalled" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const entry = MEM_BASE + 0x1A00;
    for (state.windows_guest_threads, 0..) |*thread, index| {
        thread.* = .{ .status = .runnable, .handle = 0x1000 + index, .created_step = 100 + index };
    }
    state.windows_guest_threads[9].status = .completed;
    state.windows_guest_threads[5].status = .completed;
    state.registerWindowsThreadWaitObject(0x1005);

    try testing.expect(state.enqueueWindowsGuestThread(0x2000, entry, 0, 0, false));
    try testing.expectEqual(@as(u64, 0x2000), state.windows_guest_threads[5].handle);
    try testing.expectEqual(@as(u64, 1), state.windows_thread_slots_recycled);
    try testing.expectEqual(@as(?bool, true), state.windowsWaitObjectReady(0x1005));
    try testing.expectEqual(WindowsGuestThreadStatus.completed, state.windows_guest_threads[9].status);

    // With no finished thread left to give up its slot, creation is refused.
    state.windows_guest_threads[9].status = .runnable;
    try testing.expect(!state.enqueueWindowsGuestThread(0x2001, entry, 0, 0, false));
    try testing.expectEqual(@as(u64, 1), state.windows_thread_table_full);
}

test "a worker's PAUSE ends its slice; the owner's does not" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.noteWindowsGuestPause();
    try testing.expect(!state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 0), state.windows_guest_pause_yields);

    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xC3 };
    state.windows_active_guest_thread_slot = 3;
    state.noteWindowsGuestPause();
    try testing.expect(state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 1), state.windows_guest_pause_yields);
    try testing.expectEqual(@as(u64, 1), parallel_metrics.load(u64, &state.windows_guest_threads[3].pause_hints));

    state.parallel_guest_execution = true;
    state.windows_guest_slice_yield_requested = false;
    state.noteWindowsGuestPause();
    try testing.expectEqual(@as(u64, 1), state.windows_guest_pause_yields);
    try testing.expectEqual(@as(u64, 2), parallel_metrics.load(u64, &state.windows_guest_threads[3].pause_hints));
    try testing.expect(!state.windows_guest_slice_yield_requested);
    for (0..255) |_| state.noteWindowsGuestPause();
    try testing.expect(state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 257), parallel_metrics.load(u64, &state.windows_guest_threads[3].pause_hints));
}

test "PAUSE fast dispatch preserves RIP, flags, and worker accounting" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const rip = MEM_BASE + 0x1A00;
    state.block_jit_enabled = false;
    state.write8(rip, 0xF3);
    state.write8(rip + 1, 0x90);
    state.regs.rip = rip;
    state.regs.rflags = 0x246;
    state.windows_guest_threads[3] = .{ .status = .running, .handle = 0xC3 };
    state.windows_active_guest_thread_slot = 3;

    try testing.expect(state.step());
    try testing.expectEqual(rip + 2, state.regs.rip);
    try testing.expectEqual(@as(u64, 0x246), state.regs.rflags);
    try testing.expectEqual(rip, state.last_instruction_rip);
    try testing.expectEqual(@as(u64, 1), state.windows_guest_threads[3].pause_hints);
    try testing.expect(state.windows_guest_slice_yield_requested);
}

test "parallel PAUSE decode recognizes changed code bytes" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    const rip = MEM_BASE + 0x1A00;
    state.write8(rip, 0xF3);
    state.write8(rip + 1, 0x90);
    state.regs.rip = rip;
    state.parallel_guest_execution = true;

    const pause = state.decodeAt() orelse return error.ExpectedPause;
    try testing.expectEqual(Op.nop, pause.op);
    try testing.expectEqual(@as(u8, 2), pause.len);
    state.write8(rip, 0x90);
    const changed = state.decodeAt() orelse return error.ExpectedChangedInstruction;
    try testing.expectEqual(Op.nop, changed.op);
    try testing.expectEqual(@as(u8, 1), changed.len);
}

test "parallel PAUSE batches preserve hint counts, flags, and the exact yield boundary" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.block_jit_enabled = false;
    state.parallel_guest_execution = true;
    state.windows_active_guest_thread_slot = 3;
    const rip = MEM_BASE + 0x1A00;
    for (0..8) |i| {
        state.write8(rip + i * 2, 0xF3);
        state.write8(rip + i * 2 + 1, 0x90);
    }
    state.write8(rip + 16, 0x90);
    state.regs.rip = rip;
    state.regs.rflags = 0xAD7;
    // The first hint remains an immediate scheduling point.
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    try testing.expectEqual(rip + 2, state.regs.rip);
    state.windows_guest_slice_yield_requested = false;
    state.windows_slice_pause_yield = false;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 7), state.step_retired);
    try testing.expectEqual(rip + 16, state.regs.rip);
    try testing.expectEqual(@as(u64, 8), state.windows_guest_threads[3].pause_hints);
    try testing.expectEqual(@as(u64, 0xAD7), state.regs.rflags);
    try testing.expectEqual(rip + 14, state.last_instruction_rip);
    // A 256-hint boundary in the middle of a bundle must stop there.
    state.windows_guest_threads[3].pause_hints = 254;
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 3), state.step_retired);
    try testing.expectEqual(rip + 6, state.regs.rip);
    try testing.expectEqual(@as(u64, 257), state.windows_guest_threads[3].pause_hints);
    try testing.expect(state.windows_guest_slice_yield_requested);
    state.windows_guest_slice_yield_requested = false;
    state.windows_slice_pause_yield = false;
    state.windows_guest_threads[3].spin.capture_remaining = 5;
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    // A changed instruction must be observed instead of batched as PAUSE.
    state.windows_guest_threads[3].spin.capture_remaining = 0;
    state.write8(rip + 2, 0x90);
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    try testing.expectEqual(rip + 2, state.regs.rip);
}

test "parallel PAUSE batches production benchmark (ROSETTE_VECTOR_BENCH=1)" {
    if (std.c.getenv("ROSETTE_VECTOR_BENCH") == null) return error.SkipZigTest;
    for ([_]bool{ false, true }) |batched| {
        const state = try testing.allocator.create(ElfState);
        defer testing.allocator.destroy(state);
        state.* = ElfState.init(testing.allocator);
        defer state.deinit();
        state.parallel_guest_execution = true;
        state.block_jit_enabled = false;
        state.parallel_pause_batches_enabled = batched;
        state.windows_active_guest_thread_slot = 3;
        const rip = MEM_BASE + 0x1A00;
        for (0..8) |i| {
            state.write8(rip + i * 2, 0xF3);
            state.write8(rip + i * 2 + 1, 0x90);
        }
        var started: std.c.timespec = undefined;
        var finished: std.c.timespec = undefined;
        _ = std.c.clock_gettime(.MONOTONIC, &started);
        var retired: u64 = 0;
        var dispatches: u64 = 0;
        while (retired < 500_000) {
            state.regs.rip = rip;
            state.windows_guest_slice_yield_requested = false;
            state.windows_slice_pause_yield = false;
            try testing.expect(state.step());
            retired += state.step_retired;
            dispatches += 1;
        }
        _ = std.c.clock_gettime(.MONOTONIC, &finished);
        const ns = (finished.sec - started.sec) * std.time.ns_per_s + finished.nsec - started.nsec;
        try testing.expectEqual(retired, state.windows_guest_threads[3].pause_hints);
        std.debug.print("PAUSE BENCH: batched={} retired={d} dispatches={d} elapsed_us={d}\n", .{ batched, retired, dispatches, @divTrunc(ns, 1000) });
    }
}

test "parallel PAUSE batches retain single-instruction trace and clock boundaries" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.block_jit_enabled = false;
    state.parallel_guest_execution = true;
    state.windows_active_guest_thread_slot = 3;
    state.windows_guest_threads[3].pause_hints = 8;
    const rip = MEM_BASE + 0x1A00;
    for (0..8) |i| {
        state.write8(rip + i * 2, 0xF3);
        state.write8(rip + i * 2 + 1, 0x90);
    }
    state.trace_rip_start = rip;
    state.trace_rip_end = rip + 16;
    state.trace_rip_limit = 0;
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    try testing.expectEqual(@as(u64, 0), state.trace_rip_events);
    state.trace_rip_start = null;
    state.guest_clock.source = .retired_instructions;
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    state.guest_clock.source = .host_monotonic;
    state.parallel_guest_execution = false;
    state.regs.rip = rip;
    try testing.expect(state.step());
    try testing.expectEqual(@as(u32, 1), state.step_retired);
    try testing.expectEqual(@as(u64, 0), state.parallel_pause_batched_instructions.load(.monotonic));
}

test "clock reads piling up inside one worker slice end that slice" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    // The owner has no slice to end.
    state.noteWindowsGuestClockRead();
    try testing.expectEqual(@as(u32, 0), state.windows_slice_clock_reads);

    state.windows_guest_threads[6] = .{ .status = .running, .handle = 0xC6 };
    state.windows_active_guest_thread_slot = 6;
    for (0..WINDOWS_CLOCK_POLL_YIELD_READS - 1) |_| state.noteWindowsGuestClockRead();
    try testing.expect(!state.windows_guest_slice_yield_requested);
    state.noteWindowsGuestClockRead();
    try testing.expect(state.windows_guest_slice_yield_requested);
    try testing.expectEqual(@as(u64, 1), state.windows_clock_poll_yields);
}

test "the guest wall clock a timed wait measures against is the one GetSystemTimeAsFileTime reports" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.ticks = 3 * WINDOWS_GUEST_CLOCK_HZ + WINDOWS_GUEST_CLOCK_HZ / 2;
    try testing.expectEqual(WINDOWS_GUEST_FILETIME_BASE + 35_000_000, state.windowsGuestFileTime());
    // An absolute timespec 1.5 s after "now" asks for 1500 ms.
    const now_seconds = (state.windowsGuestFileTime() - WINDOWS_FILETIME_UNIX_EPOCH) / 10_000_000;
    const timespec = MEM_BASE + 0x3400;
    state.write64(timespec, now_seconds + 2);
    state.write32(timespec + 8, 0);
    try testing.expectEqual(@as(?u64, 1500), state.windowsPthreadTimespecMilliseconds(timespec, false));
    state.write64(timespec, 0);
    state.write32(timespec + 8, 1);
    try testing.expectEqual(@as(?u64, 1), state.windowsPthreadTimespecMilliseconds(timespec, true));
}

test "the precise-time fast import reads the published guest clock value" {
    var state = ElfState.init(testing.allocator);
    defer state.deinit();
    state.guest_clock.ticks = 100;
    state.guest_clock.base_nanos = 1;
    state.guest_clock.stride = WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE - 1;

    state.advanceWindowsGuestClock();
    try testing.expect(state.guest_clock.ticks > 100);
    // The fast read samples the clock first; the locked snapshot then
    // agrees with what it published.
    const fast_file_time = state.windowsGuestFastFileTime();
    try testing.expectEqual(state.windowsGuestFileTime(), fast_file_time);
}

test "every instruction form Xenia's x64 JIT can emit under Rosette's CPUID decodes and executes" {
    // xenia_jit_corpus.txt is tools/gen_xenia_jit_corpus.py's output: every
    // mnemonic Xenia's x64 backend calls, in every operand form an assembler
    // accepts, restricted to the extensions Rosette's `xenia` CPUID profile
    // advertises. The 2026-09-14 run died in title code at 0xa0535c03 on one
    // such form; this names all of them before a run has to find one.
    const corpus = @embedFile("../../xenia_jit_corpus.txt");
    var state = ElfState.init(testing.allocator);
    // One form per step: this drives the decoder and executor one
    // instruction at a time at one address, and a translated block there
    // would run on into whatever bytes follow the form.
    state.block_jit_enabled = false;
    defer state.deinit();
    const code = MEM_BASE + 0x1000;
    const data = MEM_BASE + 0x40000;
    var failures: usize = 0;
    var first_failure: []const u8 = "";
    var lines = std.mem.splitScalar(u8, corpus, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '|');
        const hex = fields.next() orelse continue;
        var bytes = [_]u8{0x90} ** 16;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, hex, ' ');
        while (tokens.next()) |token| {
            if (count == bytes.len) break;
            bytes[count] = try std.fmt.parseInt(u8, token, 16);
            count += 1;
        }
        const decoded = decodeInsn(bytes[0..count]);
        if (decoded.op == .invalid or decoded.len != count) {
            if (failures == 0) first_failure = line;
            failures += 1;
            continue;
        }
        for (bytes, 0..) |byte, offset| state.write8(code + offset, byte);
        const segments = state.regs.segments;
        state.regs = .{};
        state.regs.segments = segments;
        // Every base register addresses readable memory, the index register
        // is zero, and CL is a shift count of one.
        state.regs.rax = data;
        state.regs.rbx = data;
        state.regs.rcx = 1;
        state.regs.rsi = data;
        state.regs.rdi = data;
        state.regs.rbp = data;
        state.regs.rsp = MEM_BASE + 0x80000;
        state.regs.r8 = data;
        state.regs.r9 = data;
        state.regs.r10 = data + 3;
        state.regs.r11 = data;
        state.regs.r12 = data;
        state.regs.r13 = 0;
        state.regs.r14 = data;
        state.regs.r15 = data;
        state.regs.rip = code;
        state.terminated = false;
        state.faulted = false;
        state.termination_reason = .unknown;
        _ = state.step();
        if (state.termination_reason == .unimplemented_instruction) {
            if (failures == 0) first_failure = line;
            failures += 1;
        }
    }
    if (failures != 0) std.debug.print("{d} Xenia JIT form(s) fail; the first is {s}\n", .{ failures, first_failure });
    try testing.expectEqual(@as(usize, 0), failures);
}
