const std = @import("std");
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const compat_runtime = @import("macho_compat_runtime");
const launch_argument_accelerator = @import("diagnostics").launch_argument_accelerator;
const decoder = @import("macho_core").decoder;
const utils = @import("macho_core").utils;
const constants = @import("macho_core").constants;

const calculateBulkConstructionRange = utils.calculateBulkConstructionRange;
const isAsciiBytes = utils.isAsciiBytes;
const repairAsciiCodepointBlock = utils.repairAsciiCodepointBlock;
const isPatchDbNullIsArraySequence = utils.isPatchDbNullIsArraySequence;
const profileIdFromUserDevice = utils.profileIdFromUserDevice;
const decodeInsn = decoder.decodeInsn;

const TomlAsciiBlock = @import("macho_core").types.TomlAsciiBlock;

const GUEST_LOG_BUFFER_SIZE = constants.GUEST_LOG_BUFFER_SIZE;
const TOML_CODEPOINT_CAPACITY = constants.TOML_CODEPOINT_CAPACITY;
const TOML_CODEPOINT_STRIDE = constants.TOML_CODEPOINT_STRIDE;
const TOML_READER_ISTREAM_OFFSET = constants.TOML_READER_ISTREAM_OFFSET;
const TOML_CODEPOINTS_OFFSET = constants.TOML_CODEPOINTS_OFFSET;
const TOML_CODEPOINT_CURRENT_OFFSET = constants.TOML_CODEPOINT_CURRENT_OFFSET;
const TOML_CODEPOINT_COUNT_OFFSET = constants.TOML_CODEPOINT_COUNT_OFFSET;
const TOML_UTF8_READER_MIN_SIZE = constants.TOML_UTF8_READER_MIN_SIZE;

pub fn handleLibcppBasicStringSubstr(self: anytype) bool {
    const entry = self.internal_targets.libcxx_basic_string_substr;
    if (entry == 0 or self.regs.rip != entry) return false;

    const destination = self.regs.rdi;
    const source_object = self.regs.rsi;
    const position = self.regs.rdx;
    const count = self.regs.rcx;
    const source_view = compat_runtime.libcppStringView(self, source_object) orelse {
        machoCapturePrint(
            "macho-processor: libc++ basic_string::substr rejected unreadable source object=0x{x} destination=0x{x}\n",
            .{ source_object, destination },
        );
        return false;
    };
    if (source_view.length > 1 << 20 or
        self.guestMemoryConst(source_view.address, source_view.length) == null)
    {
        machoCapturePrint(
            "macho-processor: libc++ basic_string::substr rejected corrupt source: object=0x{x} data=0x{x} length={d} pos={d} count={d}\n",
            .{ source_object, source_view.address, source_view.length, position, count },
        );
        return false;
    }
    if (position > source_view.length) {
        machoCapturePrint(
            "macho-processor: libc++ basic_string::substr out-of-range delegated to guest: source_length={d} pos={d} count={d}\n",
            .{ source_view.length, position, count },
        );
        return false;
    }

    const source_bytes = self.guestMemoryConst(source_view.address, source_view.length).?;
    const profile_device = std.mem.startsWith(u8, source_bytes, "User_") and
        std.mem.endsWith(u8, source_bytes, ":");
    var preview_buffer: [256]u8 = undefined;
    const preview_length = @min(source_bytes.len, preview_buffer.len);
    @memcpy(preview_buffer[0..preview_length], source_bytes[0..preview_length]);
    const preview = preview_buffer[0..preview_length];
    const result_length = compat_runtime.substringLibcppString(
        self,
        destination,
        source_object,
        position,
        count,
    ) orelse return false;
    const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null) self.read64(self.regs.rsp) else 0;
    const caller = if (return_address != 0) self.metadata.nearestSymbol(return_address) else null;
    const vfs_resolution = if (caller) |symbol|
        std.mem.indexOf(u8, symbol.name, "VirtualFileSystem11ResolvePath") != null
    else
        false;
    self.libcxx_string_substr_fast_paths +|= 1;
    if (self.libcxx_string_substr_fast_paths <= 16 or vfs_resolution or profile_device) {
        machoCapturePrint(
            "macho-processor: libc++ basic_string::substr fast path #{d}: source_object=0x{x} destination=0x{x} source_length={d} pos={d} count={d} result_length={d} caller=0x{x} {s}+0x{x} source='{s}'\n",
            .{ self.libcxx_string_substr_fast_paths, source_object, destination, source_view.length, position, count, result_length, return_address, if (caller) |symbol| symbol.name else "<unknown>", if (caller) |symbol| symbol.offset else 0, preview },
        );
    }
    if (vfs_resolution) {
        machoCapturePrint(
            "macho-processor: VFS relative-path checkpoint: mount_length={d} normalized_length={d} relative_length={d} root_resolution={}; HostPathDevice must receive only this suffix, never the User_<profile-id>: prefix\n",
            .{ position, source_view.length, result_length, result_length == 0 },
        );
    }
    if (profile_device and position == source_view.length and result_length == 0) {
        machoCapturePrint(
            "macho-processor: profile device root normalized successfully: source='{s}' pos==size and substr result is empty; ResolvePath should now return the mounted HostPathDevice root before Account child lookup\n",
            .{preview},
        );
        if (profileIdFromUserDevice(preview)) |profile_id| {
            self.logProfileHostPreflight(profile_id);
        }
    }

    self.regs.rax = destination;
    self.regs.rip = self.pop();
    return true;
}

pub fn handleInternalCompatibility(self: anytype) bool {
    if (handleLibcppBasicStringSubstr(self)) return true;
    if (handleLocalLibcppStreamCompatibility(self)) return true;
    if (self.internal_targets.xenia_cpu_feature_detector_initialize_cpu_info != 0 and
        self.regs.rip == self.internal_targets.xenia_cpu_feature_detector_initialize_cpu_info)
    {
        machoCapturePrint("macho-processor: modeled x64 CPU feature detection\n", .{});
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.xenia_vulkan_provider_vulkan_device != 0 and
        self.regs.rip == self.internal_targets.xenia_vulkan_provider_vulkan_device and
        self.regs.rdi == 0)
    {
        machoCapturePrint("macho-processor: Vulkan provider unavailable; returning null Vulkan device\n", .{});
        self.regs.rax = 0;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.page_entry_construct_at_end != 0 and
        self.regs.rip == self.internal_targets.page_entry_construct_at_end and
        handlePageEntryBulkInitialization(self))
    {
        return true;
    }
    if (self.has_xenia_compat and
        self.internal_targets.imgui_text_ex != 0 and
        self.regs.rip == self.internal_targets.imgui_text_ex)
    {
        // TextEx only contributes diagnostic/UI text. Rosette's Mach-O path
        // has no ImGui renderer, and executing the real function would enter
        // an incomplete ImGuiContext/ImGuiWindow graph (the observed fault was
        // `test byte ptr [rax+0x106]` with rax=0). Model this exact rendering
        // boundary as a void-returning no-op; do not turn arbitrary near-null
        // reads into zero-filled memory.
        const return_address = if (self.guestMemoryConst(self.regs.rsp, 8) != null)
            self.read64(self.regs.rsp)
        else
            0;
        if (return_address == 0 or !self.isExecutableAddress(return_address)) {
            machoCapturePrint(
                "macho-processor: ImGui TextEx compatibility rejected: invalid return target rsp=0x{x} entry=0x{x} text=0x{x} text_end=0x{x} flags=0x{x} return=0x{x} executable={}\n",
                .{ self.regs.rsp, self.regs.rip, self.regs.rdi, self.regs.rsi, self.regs.rdx, return_address, return_address != 0 and self.isExecutableAddress(return_address) },
            );
            return false;
        }
        self.imgui_text_ex_noops +|= 1;
        if (self.imgui_text_ex_noops == 1 or self.imgui_text_ex_noops % 256 == 0) {
            machoCapturePrint(
                "macho-processor: ImGui TextEx compatibility no-op #{d}: entry=0x{x} text=0x{x} text_end=0x{x} flags=0x{x} return=0x{x} phase={s}\n",
                .{ self.imgui_text_ex_noops, self.regs.rip, self.regs.rdi, self.regs.rsi, self.regs.rdx, return_address, @tagName(self.startup.phase) },
            );
        }
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_settings_push_back != 0 and
        self.regs.rip == self.internal_targets.imgui_settings_push_back)
    {
        _ = self.appendTrivialVector(self.regs.rdi, self.regs.rsi, 0x48, 8);
        if (!self.terminated) self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_create_context != 0 and
        self.regs.rip == self.internal_targets.imgui_create_context)
    {
        // ImGui::CreateContext(ImFontAtlas* atlas = NULL)
        // rdi = atlas (optional), return = ImGuiContext*
        // Allocate a minimal ImGuiContext (we just need the GImGui global set)
        // The actual context struct is complex, but we just need to set GImGui
        // to a valid address so GetCurrentWindow doesn't crash.
        const ctx_size: u64 = 0x2000; // ImGuiContext is large, allocate generously
        const ctx = self.memory_forwarder.allocate(self, ctx_size, 16) orelse 0;
        if (ctx != 0) {
            // ImGui's GImGui global is typically at a known offset from the context
            // For simplicity, we'll store the context pointer at a known location
            // and ensure GetCurrentWindow can find it.
            // The actual GImGui global location varies; we'll write the context
            // pointer to the first qword of the allocated block as a proxy.
            _ = self.write64(ctx, ctx);
        }
        self.regs.rax = ctx;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_get_current_window != 0 and
        self.regs.rip == self.internal_targets.imgui_get_current_window)
    {
        // ImGui::GetCurrentWindow() - ensure context exists
        // Check if GImGui global is set; if not, create a context first
        // The GImGui global location is binary-specific; we'll try to find it
        // by looking at known offsets or create a context on demand.
        // For now, if we have a context from CreateContext, return it.
        // This is a simplified implementation - in reality we'd need to
        // find the actual GImGui global address.
        if (self.internal_targets.imgui_create_context != 0) {
            // Reuse the create context logic
            const ctx_size: u64 = 0x2000;
            const ctx = self.memory_forwarder.allocate(self, ctx_size, 16) orelse 0;
            self.regs.rax = ctx;
        } else {
            self.regs.rax = 0;
        }
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_mem_alloc != 0 and
        self.regs.rip == self.internal_targets.imgui_mem_alloc)
    {
        self.regs.rax = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_mem_free != 0 and
        self.regs.rip == self.internal_targets.imgui_mem_free)
    {
        self.memory_forwarder.releaseFrom(self.regs.rdi, self.regs.rip);
        self.vtable_tracker.forgetAddress(self.regs.rdi);
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_default_malloc != 0 and
        self.regs.rip == self.internal_targets.imgui_default_malloc)
    {
        self.regs.rax = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.imgui_default_free != 0 and
        self.regs.rip == self.internal_targets.imgui_default_free)
    {
        self.memory_forwarder.releaseFrom(self.regs.rdi, self.regs.rip);
        self.vtable_tracker.forgetAddress(self.regs.rdi);
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.parse_launch_arguments != 0 and
        self.regs.rip == self.internal_targets.parse_launch_arguments)
    {
        self.startup.enter(.launch_arguments, self.executed_steps);
        capturePositionalLaunchOptions(self);
    }
    if (self.internal_targets.initialize_logging != 0 and
        self.regs.rip == self.internal_targets.initialize_logging)
    {
        self.startup.enter(.logging, self.executed_steps);
        const app_name = self.guestMemoryConst(self.regs.rdi, @min(self.regs.rsi, 1024)) orelse "";
        if (self.logging.initialize(app_name)) {
            if (self.guest_log_buffer_address == 0) {
                self.guest_log_buffer_address = self.guestAlloc(GUEST_LOG_BUFFER_SIZE, 16) orelse return false;
            }
            self.regs.rip = self.pop();
            self.startup.enter(.logging_ready, self.executed_steps);
            return true;
        }
    }
    if (self.internal_targets.shutdown_logging != 0 and
        self.regs.rip == self.internal_targets.shutdown_logging and
        self.logging.shutdown())
    {
        self.regs.rip = self.pop();
        return true;
    }
    if (handleGuestLogBridge(self)) return true;
    for (self.internal_targets.cvar_add_to_launch_options[0..self.internal_targets.cvar_add_to_launch_options_count]) |target| {
        if (self.regs.rip != target) continue;
        const view = compat_runtime.libcppStringView(self, self.regs.rdi + 8) orelse return false;
        const name = self.guestMemoryConst(view.address, view.length) orelse return false;
        if (self.launch_options.shouldRegister(name)) return false;
        if (self.launch_options.registrations_skipped == 1 or
            self.launch_options.registrations_skipped % 100 == 0)
        {
            machoCapturePrint(
                "macho-processor: launch option fast path skipped {d} unused registration(s); latest={s}\n",
                .{ self.launch_options.registrations_skipped, name },
            );
        }
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.cxxopts_split_option_names != 0 and
        self.regs.rip == self.internal_targets.cxxopts_split_option_names)
    {
        return handleCxxoptsSplitOptionNames(self);
    }
    if (self.internal_targets.libcxx_basic_streambuf_pubsetbuf != 0 and
        self.regs.rip == self.internal_targets.libcxx_basic_streambuf_pubsetbuf)
    {
        self.regs.rax = self.libcxx_streams.handlePubsetbuf(self.regs.rdi, self.regs.rsi, self.regs.rdx);
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.libcxx_basic_ifstream_default_constructor != 0 and
        self.regs.rip == self.internal_targets.libcxx_basic_ifstream_default_constructor)
    {
        if (!self.libcxx_streams.constructIfstream(self, self.regs.rdi)) return false;
        self.regs.rax = self.regs.rdi;
        self.regs.rip = self.pop();
        return true;
    }
    if ((self.internal_targets.libcxx_basic_ifstream_destructor_1 != 0 and
        self.regs.rip == self.internal_targets.libcxx_basic_ifstream_destructor_1) or
        (self.internal_targets.libcxx_basic_ifstream_destructor_2 != 0 and
            self.regs.rip == self.internal_targets.libcxx_basic_ifstream_destructor_2))
    {
        self.libcxx_streams.destroyIfstream(self, self.regs.rdi);
        self.regs.rip = self.pop();
        return true;
    }
    if ((self.internal_targets.libcxx_getline != 0 and self.regs.rip == self.internal_targets.libcxx_getline) or
        (self.internal_targets.libcxx_getline_delimiter != 0 and self.regs.rip == self.internal_targets.libcxx_getline_delimiter))
    {
        const delimiter: u8 = if (self.regs.rip == self.internal_targets.libcxx_getline_delimiter) @truncate(self.regs.rdx) else '\n';
        _ = self.libcxx_streams.readLine(self, self.regs.rdi, self.regs.rsi, delimiter);
        self.regs.rax = self.regs.rdi;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.print_config_to_log != 0 and
        self.regs.rip == self.internal_targets.print_config_to_log)
    {
        self.startup.enter(.config_load, self.executed_steps);
        if (self.diagnostic_text.buildConfigDump(self, &self.fs_forwarder, self.regs.rdi)) |dump| {
            const emitted = self.emitGuestLog('i', dump.address, dump.length);
            self.logging.recordEmission(dump.length, emitted);
            self.regs.rip = self.pop();
            return true;
        }
    }
    return false;
}

pub fn handlePageEntryBulkInitialization(self: anytype) bool {
    const split_buffer = self.regs.rdi;
    const count = self.regs.rsi;
    if (self.guestMemoryConst(split_buffer, 32) == null) return false;

    const begin = self.read64(split_buffer + 8);
    const end = self.read64(split_buffer + 16);
    const capacity_end = self.read64(split_buffer + 24);
    if (begin == 0 or end < begin or capacity_end < end) return false;

    const range = calculateBulkConstructionRange(begin, end, capacity_end, count, 16) orelse return false;
    if (range.byte_count != 0) {
        const destination = self.guestMemory(end, range.byte_count) orelse return false;
        @memset(destination, 0);
    }
    self.write64(split_buffer + 16, range.new_end);
    self.page_entry_bulk_initializations +|= 1;
    self.page_entry_bulk_bytes +|= range.byte_count;
    const return_address = self.read64(self.regs.rsp);
    const caller = self.metadata.nearestSymbol(return_address);
    machoCapturePrint(
        "macho-processor: bulk default construction: PageEntry count={d} bytes={d} range=0x{x}-0x{x} return={s}+0x{x}\n",
        .{ count, range.byte_count, end, range.new_end, if (caller) |resolved| resolved.name else "<unknown>", if (caller) |resolved| resolved.offset else 0 },
    );
    self.regs.rip = self.pop();
    return !self.terminated;
}

pub fn handleLocalLibcppStreamCompatibility(self: anytype) bool {
    // Fast-reject outside the populated target span so the hash probe does
    // not run on every interpreted instruction.
    if (self.libcpp_stream_target_max == 0 or
        self.regs.rip < self.libcpp_stream_target_min or
        self.regs.rip > self.libcpp_stream_target_max) return false;
    const symbol = self.local_libcpp_stream_targets.get(self.regs.rip) orelse return false;
    const resolution = self.libcxx_streams.dispatch(self, &self.fs_forwarder, symbol) orelse return false;
    switch (resolution) {
        .handled => |value| self.regs.rax = value,
        .handled_void => {},
    }
    self.regs.rip = self.pop();
    return true;
}

pub fn capturePositionalLaunchOptions(self: anytype) void {
    if (self.positional_options_captured) return;
    self.positional_options_captured = true;

    const vector = self.regs.r8;
    const begin = self.read64(vector);
    const end = self.read64(vector + 8);
    if (begin == 0 or end < begin or (end - begin) % 24 != 0) {
        machoCapturePrint("macho-processor: launch option acceleration could not decode positional option vector at 0x{x}\n", .{vector});
        return;
    }
    const count = @min((end - begin) / 24, launch_argument_accelerator.MAX_REQUESTED_OPTIONS);
    for (0..@as(usize, @intCast(count))) |index| {
        const object = begin + index * 24;
        const view = compat_runtime.libcppStringView(self, object) orelse continue;
        const name = self.guestMemoryConst(view.address, view.length) orelse continue;
        self.launch_options.request(name);
        machoCapturePrint("macho-processor: launch option acceleration retained positional option: {s}\n", .{name});
    }
}

pub fn handleGuestLogBridge(self: anytype) bool {
    if (self.internal_targets.guest_log_get_thread_buffer != 0 and
        self.regs.rip == self.internal_targets.guest_log_get_thread_buffer)
    {
        if (self.guest_log_buffer_address == 0) {
            self.guest_log_buffer_address = self.guestAlloc(GUEST_LOG_BUFFER_SIZE, 16) orelse return false;
            machoCapturePrint(
                "macho-processor: synchronous Xenia log bridge enabled at buffer=0x{x}\n",
                .{self.guest_log_buffer_address},
            );
        }
        self.regs.rax = self.guest_log_buffer_address;
        self.regs.rdx = GUEST_LOG_BUFFER_SIZE;
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.guest_log_append_formatted != 0 and
        self.regs.rip == self.internal_targets.guest_log_append_formatted)
    {
        var emitted = false;
        if (self.guest_log_buffer_address != 0) {
            emitted = self.emitGuestLog(self.regs.rsi, self.guest_log_buffer_address, self.regs.rdx);
        }
        self.logging.recordEmission(self.regs.rdx, emitted);
        self.regs.rip = self.pop();
        return true;
    }
    if (self.internal_targets.guest_log_append_view != 0 and
        self.regs.rip == self.internal_targets.guest_log_append_view)
    {
        const emitted = self.emitGuestLog(self.regs.rsi, self.regs.rdx, self.regs.rcx);
        self.logging.recordEmission(self.regs.rcx, emitted);
        self.regs.rip = self.pop();
        return true;
    }
    return false;
}

pub fn handleCxxoptsSplitOptionNames(self: anytype) bool {
    const output = self.regs.rdi;
    const input = self.regs.rsi;
    const view = compat_runtime.libcppStringView(self, input) orelse return false;
    const bytes = self.guestMemoryConst(view.address, view.length) orelse return false;
    if (bytes.len == 0 or self.guestMemory(output, 24) == null) return false;

    var token_count: u64 = 1;
    var token_start: usize = 0;
    for (bytes, 0..) |byte, index| {
        if (byte != ',') continue;
        var end = index;
        while (end > token_start and bytes[end - 1] == ' ') end -= 1;
        while (token_start < end and bytes[token_start] == ' ') token_start += 1;
        if (token_start == end) return false;
        token_count += 1;
        token_start = index + 1;
    }
    var final_end = bytes.len;
    while (final_end > token_start and bytes[final_end - 1] == ' ') final_end -= 1;
    while (token_start < final_end and bytes[token_start] == ' ') token_start += 1;
    if (token_start == final_end) return false;

    const storage_size = std.math.mul(u64, token_count, 24) catch return false;
    const storage = self.guestAlloc(storage_size, 8) orelse return false;
    @memset(self.guestMemory(output, 24).?, 0);

    token_start = 0;
    var token_index: u64 = 0;
    var cursor: usize = 0;
    while (cursor <= bytes.len) : (cursor += 1) {
        if (cursor != bytes.len and bytes[cursor] != ',') continue;
        var start = token_start;
        var end = cursor;
        while (start < end and bytes[start] == ' ') start += 1;
        while (end > start and bytes[end - 1] == ' ') end -= 1;
        const object = storage + token_index * 24;
        if (!compat_runtime.initLibcppString(self, object, view.address + start, end - start)) return false;
        token_index += 1;
        token_start = cursor + 1;
    }

    self.write64(output, storage);
    self.write64(output + 8, storage + storage_size);
    self.write64(output + 16, storage + storage_size);
    self.cxxopts_split_accelerations += 1;
    if (self.cxxopts_split_accelerations == 1 or self.cxxopts_split_accelerations % 250 == 0) {
        machoCapturePrint(
            "macho-processor: cxxopts option-name fast path handled {d} call(s)\n",
            .{self.cxxopts_split_accelerations},
        );
    }
    self.regs.rax = output;
    self.regs.rip = self.pop();
    return true;
}

pub fn handleTomlAsciiFastPath(self: anytype) bool {
    const entry = self.toml_ascii_entry orelse return false;
    if (self.regs.rip != entry) return false;

    const raw_length = self.regs.rsi;
    const data_ptr = self.regs.rdi;

    const expected_length = self.libcxx_streams.findPatchTomlByteCount();
    const length_mismatch = raw_length > 1024 * 1024 or
        (expected_length != null and raw_length != expected_length.?);
    const safe_length: u64 = if (length_mismatch) expected_length orelse 0 else raw_length;
    const have_bytes = if (length_mismatch and expected_length == null)
        null
    else
        self.guestMemoryConst(data_ptr, safe_length);
    const ascii = if (have_bytes) |bytes| isAsciiBytes(bytes) else false;
    if (have_bytes == null and raw_length > 1024 * 1024) {
        machoCapturePrint(
            "macho-processor: toml++ is_ascii fast path UNCERTAIN: pointer=0x{x} raw_bytes={d} forced_ascii=false; parser will use slow path\n",
            .{ data_ptr, raw_length },
        );
    } else if (have_bytes == null) {
        machoCapturePrint(
            "macho-processor: toml++ is_ascii fast path rejected unreadable input: pointer=0x{x} raw_bytes={d} capped={d}\n",
            .{ data_ptr, raw_length, safe_length },
        );
    } else if (length_mismatch) {
        machoCapturePrint(
            "macho-processor: toml++ is_ascii ABI LENGTH MISMATCH: pointer=0x{x} raw={d} expected={?d} bounded={d} ascii={}; no guest parser fields were modified\n",
            .{ data_ptr, raw_length, expected_length, safe_length, ascii },
        );
        self.libcxx_streams.dumpPatchTomlDiagnostics("is_ascii length mismatch");
    }

    if (!length_mismatch and ascii and safe_length <= TOML_CODEPOINT_CAPACITY and self.regs.rbp >= 0x128) {
        const reader_slot = self.regs.rbp - 0x128;
        if (self.guestMemoryConst(reader_slot, 8) != null) {
            const reader = self.read64(reader_slot);
            if (reader != 0 and self.guestMemoryConst(reader, TOML_UTF8_READER_MIN_SIZE) != null) {
                const istream = self.read64(reader + TOML_READER_ISTREAM_OFFSET);
                if (self.libcxx_streams.isActivePatchTomlIstream(istream)) {
                    var block = TomlAsciiBlock{ .reader = reader, .length = @intCast(safe_length) };
                    @memcpy(block.bytes[0..block.length], have_bytes.?[0..block.length]);
                    self.toml_ascii_block = block;
                }
            }
        }
    }

    self.regs.rax = @intFromBool(ascii);
    self.regs.rip = self.pop();
    self.toml_ascii_fast_paths +|= 1;
    if (self.toml_ascii_fast_paths <= 8 or self.toml_ascii_fast_paths % 256 == 0) {
        machoCapturePrint(
            "macho-processor: toml++ is_ascii fast path #{d}: pointer=0x{x} bytes={d} ascii={} return=0x{x}\n",
            .{ self.toml_ascii_fast_paths, data_ptr, safe_length, ascii, self.regs.rip },
        );
    }
    return true;
}

pub fn handleTomlReadNextIntegrity(self: anytype) void {
    const entry = self.toml_read_next_entry orelse return;
    if (self.regs.rip != entry) return;
    const pending = self.toml_ascii_block orelse return;
    if (pending.validated or self.regs.rdi != pending.reader) return;

    const reader = pending.reader;
    const expected = pending.bytes[0..pending.length];
    const storage_length: u64 = @as(u64, pending.length) * @as(u64, TOML_CODEPOINT_STRIDE);
    const storage = self.guestMemory(reader + TOML_CODEPOINTS_OFFSET, storage_length) orelse {
        machoCapturePrint(
            "macho-processor: toml++ ASCII codepoint checkpoint FAILED: reader=0x{x} storage is not writable bytes={d}\n",
            .{ reader, storage_length },
        );
        self.libcxx_streams.dumpPatchTomlDiagnostics("codepoint block unavailable");
        if (self.toml_ascii_block) |*block| block.validated = true;
        return;
    };

    const guest_current = self.read64(reader + TOML_CODEPOINT_CURRENT_OFFSET);
    const guest_count = self.read64(reader + TOML_CODEPOINT_COUNT_OFFSET);
    const report = repairAsciiCodepointBlock(storage, expected);
    if (guest_count != pending.length) {
        self.write64(reader + TOML_CODEPOINT_COUNT_OFFSET, pending.length);
    }

    if (guest_current > pending.length or guest_count != pending.length or report.scalar_repairs != 0 or report.raw_repairs != 0) {
        machoCapturePrint(
            "macho-processor: toml++ codepoint integrity mismatch repaired from host-validated ASCII bytes; current index was left unchanged\n",
            .{},
        );
        self.libcxx_streams.dumpPatchTomlDiagnostics("ASCII codepoint integrity mismatch");
    }
    if (self.toml_ascii_block) |*block| block.validated = true;
}

pub fn handlePatchDbEmptyPatchArray(self: anytype) bool {
    if (self.regs.rdi != 0 or !self.libcxx_streams.latestPatchSchemaHasEmptyPatchSet()) return false;
    const symbol = self.metadata.nearestSymbol(self.regs.rip) orelse return false;
    if (std.mem.indexOf(u8, symbol.name, "PatchDB13ReadPatchFile") == null or symbol.offset != 0x419) return false;
    const bytes = self.guestMemoryConst(self.regs.rip, 14) orelse return false;
    if (!isPatchDbNullIsArraySequence(bytes)) return false;

    self.patch_db_empty_array_recoveries +|= 1;
    self.libcxx_streams.logEmptyPatchCompatibility("empty-patch compatibility");
    machoCapturePrint(
        "macho-processor: PatchDB empty-patch compatibility #{d}: rip=0x{x} {s}+0x{x} patch_node=0x0; skipping null virtual is_array() call and selecting Xenia's existing non-array return path at 0x{x}\n",
        .{ self.patch_db_empty_array_recoveries, self.regs.rip, symbol.name, symbol.offset, self.regs.rip + 14 },
    );
    machoCapturePrint(
        "macho-processor: PatchDB compatibility semantics: equivalent source guard is if (!patch_array || !patch_array->is_array()) return patch_file; parser output and decoded instruction semantics were not modified\n",
        .{},
    );
    self.regs.rax = 0;
    self.setFlagsLogic(0, .bits8);
    self.regs.rip += 14;
    return true;
}

pub fn logStalledInstructionDetails(self: anytype) void {
    const bytes = self.guestMemoryConst(self.regs.rip, 16) orelse {
        machoCapturePrint("macho-processor: stuck-pc decode unavailable: rip=0x{x} instruction bytes are unreadable\n", .{self.regs.rip});
        return;
    };
    const decoded = decodeInsn(bytes);
    const symbol = self.metadata.nearestSymbol(self.regs.rip);
    self.stalled_instruction_reports +|= 1;
    machoCapturePrint(
        "macho-processor: stuck-pc decode #{d}: rip=0x{x} {s}+0x{x} op={s} len={d} bytes={any} regs(rax/rbx/rcx/rdx/rsi/rdi/rbp/rsp/rflags)=0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}/0x{x}\n",
        .{
            self.stalled_instruction_reports,
            self.regs.rip,
            if (symbol) |entry| entry.name else "<unknown>",
            if (symbol) |entry| entry.offset else 0,
            @tagName(decoded.op),
            decoded.len,
            bytes,
            self.regs.rax,
            self.regs.rbx,
            self.regs.rcx,
            self.regs.rdx,
            self.regs.rsi,
            self.regs.rdi,
            self.regs.rbp,
            self.regs.rsp,
            self.regs.rflags,
        },
    );
    self.dumpRecentTrace();
    machoCapturePrint(
        "macho-processor: unchanged execution-state capture complete; execution remains active and scheduler recovery is still permitted\n",
        .{},
    );
}
