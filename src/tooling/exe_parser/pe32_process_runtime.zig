//! Small, bounded PE32 process model for bootstrap loaders that create a
//! suspended child, inject one PE32 DLL with LoadLibraryA, then resume it.
//! This is not a general Windows process or GUI implementation.
const std = @import("std");
const x86_asm = @import("x86_asm");
const Executor = x86_asm.instruction_operations.Executor;
const execution_engine = x86_asm.execution_engine;
const win32_thunks = x86_asm.win32_thunks;
const parser = @import("pe_parser.zig");
const imports = @import("imports/imports.zig");
const image_loader = @import("pe32_image_loader.zig");
const command_line = @import("windows_command_line.zig");

const process_handle: u32 = 0xF00D_0001;
const main_thread_handle: u32 = 0xF00D_0002;
const remote_thread_handle: u32 = 0xF00D_0003;
const dll_entry_return: u32 = 0xFFFF_FF00;
const child_memory_base: u32 = 0x0040_0000;
const child_memory_size: u32 = 0x1080_0000;
const child_memory_end: u32 = child_memory_base + child_memory_size;
const child_image_base: u32 = 0x0100_0000;
const child_dll_base: u32 = 0x1000_0000;
const remote_alloc_base: u32 = 0x1010_0000;
const child_stack_reserve: u32 = 1024 * 1024 + 0x1000;
const max_image_bytes: std.Io.Limit = .limited(128 * 1024 * 1024);

fn windowTraceEnabled() bool {
    const value = std.c.getenv("ROSETTE_PE32_WINDOW_TRACE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

const Region = struct { base: u32, size: u32 };

const Child = struct {
    executor: *Executor,
    image: parser.Image,
    image_bytes: []u8,
    import_directory: imports.ImportDirectory,
    image_path: []u8,
    command_line_bytes: []u8,
    dll_image: ?parser.Image = null,
    dll_bytes: ?[]u8 = null,
    dll_import_directory: ?imports.ImportDirectory = null,
    dll_path: ?[]u8 = null,
    regions: [256]Region = undefined,
    region_count: usize = 0,
    allocation_cursor: u32 = remote_alloc_base,
    suspended: bool = true,
    resumed: bool = false,
    remote_thread_created: bool = false,
    remote_thread_finished: bool = false,
    remote_thread_exit_code: u32 = 0,
    dll_attach_succeeded: bool = false,
    dll_attach_steps: usize = 0,
    run_steps: usize = 0,
    run_stopped_at: u32 = 0,
    active_window_message: u32 = 0,
    active_window_handle: u32 = 0,
    active_window_lparam: u32 = 0,

    fn deinit(self: *Child, allocator: std.mem.Allocator) void {
        if (self.executor.pe32_gl_context_created) {
            if (self.executor.pe32_window_host.legacy_gl_delete) |delete_context| {
                _ = delete_context(self.executor.pe32_window_host.context);
            }
        }
        if (self.dll_import_directory) |*directory| directory.deinit(allocator);
        if (self.dll_image) |image| allocator.free(image.sections);
        if (self.dll_bytes) |bytes| allocator.free(bytes);
        if (self.dll_path) |path| allocator.free(path);
        self.import_directory.deinit(allocator);
        allocator.free(self.image.sections);
        allocator.free(self.image_bytes);
        allocator.free(self.image_path);
        allocator.free(self.command_line_bytes);
        self.executor.deinit();
        allocator.destroy(self.executor);
        self.* = undefined;
    }

    fn addRegion(self: *Child, base: u32, size: u32) bool {
        if (size == 0 or self.region_count == self.regions.len) return false;
        const end = @as(u64, base) + size;
        if (base < child_memory_base or end > child_memory_end) return false;
        for (self.regions[0..self.region_count]) |region| {
            const other_end = @as(u64, region.base) + region.size;
            if (@as(u64, base) < other_end and @as(u64, region.base) < end) return false;
        }
        self.regions[self.region_count] = .{ .base = base, .size = size };
        self.region_count += 1;
        return true;
    }

    fn regionContains(self: *const Child, base: u32, size: u32) bool {
        const end = @as(u64, base) + size;
        for (self.regions[0..self.region_count]) |region| {
            const region_end = @as(u64, region.base) + region.size;
            if (base >= region.base and end <= region_end) return true;
        }
        return false;
    }
};

pub const Summary = struct {
    child_created: bool = false,
    child_resumed: bool = false,
    dll_loaded: bool = false,
    dll_attach_succeeded: bool = false,
    dll_attach_steps: usize = 0,
    child_steps: usize = 0,
    child_terminated: bool = false,
    child_exit_code: u32 = 0,
    stopped_at: u32 = 0,
    current_eip: u32 = 0,
    eax: u32 = 0,
    ebx: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    ebp: u32 = 0,
    esp: u32 = 0,
    eflags: u32 = 0,
    pending_exception: u32 = 0,
    active_window_message: u32 = 0,
    active_window_handle: u32 = 0,
    active_window_lparam: u32 = 0,
    ecx_0x50: u32 = 0,
    ecx_0x54: u32 = 0,
    stack_0: u32 = 0,
    stack_4: u32 = 0,
    stack_8: u32 = 0,
    stack_12: u32 = 0,
};

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_image_path: []const u8,
    /// Host UI callbacks are injected by the outer runner; the PE32 emulator
    /// itself remains independent of AppKit and can still be tested headless.
    window_host: Executor.Pe32WindowHost = .{},
    child: ?Child = null,
    create_process_calls: u32 = 0,
    virtual_alloc_calls: u32 = 0,
    write_memory_calls: u32 = 0,
    remote_thread_calls: u32 = 0,
    wait_calls: u32 = 0,
    resume_calls: u32 = 0,
    unsupported_calls: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, parent_image_path: []const u8) Runtime {
        return .{ .allocator = allocator, .io = io, .parent_image_path = parent_image_path };
    }

    pub fn hasInteractiveWindowHost(self: *const Runtime) bool {
        return self.window_host.pump_events != null and self.window_host.window_open != null;
    }

    pub fn deinit(self: *Runtime) void {
        if (self.child) |*child| child.deinit(self.allocator);
        self.child = null;
    }

    pub fn processApi(context: *anyopaque, executor: *Executor, api: Executor.ProcessApi) u32 {
        const self: *Runtime = @ptrCast(@alignCast(context));
        return switch (api) {
            .create_process_a => self.createProcessA(executor),
            .virtual_alloc => self.virtualAlloc(executor),
            .virtual_free => self.virtualFree(executor),
            .virtual_alloc_ex => self.virtualAllocEx(executor),
            .write_process_memory => self.writeProcessMemory(executor),
            .create_remote_thread => self.createRemoteThread(executor),
            .wait_for_single_object => self.waitForSingleObject(executor),
            .get_exit_code_thread => self.getExitCodeThread(executor),
            .resume_thread => self.resumeThread(executor),
            .close_handle => self.closeHandle(executor),
            .virtual_protect => self.virtualProtect(executor),
        };
    }

    pub fn runResumedChild(self: *Runtime, maximum_steps: usize) Summary {
        var summary = self.currentSummary();
        const child = if (self.child) |*value| value else return summary;
        if (!child.resumed or child.executor.terminated) return self.currentSummary();

        var thunks = execution_engine.ThunkTable{};
        while (child.run_steps < maximum_steps and !child.executor.terminated) {
            if (child.executor.pe32_window_callback != null) {
                if (!runPendingWindowCallbacks(child, &thunks, maximum_steps)) break;
                continue;
            }
            child.run_stopped_at = child.executor.regs.eip;
            if (!execution_engine.execNext(child.executor, &thunks)) break;
            child.run_steps += 1;
        }
        summary = self.currentSummary();
        return summary;
    }

    /// Execute queued PE32 WNDPROC calls on the guest stack. USER32 imports
    /// cannot invoke guest code directly from their host thunk, so they enqueue
    /// bounded callbacks and the owning guest-thread loop drains them between
    /// instructions. A synthetic return address lets the ordinary raw decoder
    /// execute the callback without exposing host pointers to guest code.
    fn runPendingWindowCallbacks(child: *Child, thunks: *execution_engine.ThunkTable, maximum_steps: usize) bool {
        const callback_return: u32 = 0xFFFF_FF20;
        const executor = child.executor;

        while (executor.pe32_window_callback) |callback| {
            executor.pe32_window_callback = executor.pe32_window_callback_followup;
            executor.pe32_window_callback_followup = null;
            child.active_window_message = callback.message;
            child.active_window_handle = callback.window;
            child.active_window_lparam = callback.lparam;

            const window = executor.findPe32WindowConst(callback.window) orelse continue;
            const procedure = window.procedure;
            if (procedure == 0) continue;
            if (windowTraceEnabled()) {
                std.debug.print("PE32_WINDOW: WndProc enter msg=0x{X:0>4} hwnd=0x{X:0>8} proc=0x{X:0>8} wparam=0x{X:0>8} lparam=0x{X:0>8}\n", .{
                    callback.message,
                    callback.window,
                    procedure,
                    callback.wparam,
                    callback.lparam,
                });
            }

            const saved_registers = executor.regs;
            const saved_stop_eip = executor.raw_stop_eip;
            const callback_stack_size: u32 = if (callback.create_struct) 20 + 48 else 20;
            const minimum_stack = std.math.add(u32, executor.mem.base, callback_stack_size) catch return false;
            if (saved_registers.esp < minimum_stack) return false;
            const stack = saved_registers.esp - callback_stack_size;
            if (parentSlice(executor, stack, callback_stack_size) == null) return false;

            var callback_lparam = callback.lparam;
            if (callback.create_struct) {
                // Keep CREATESTRUCTW above the callback's downward-growing
                // stack frame. Both initial creation notifications must see
                // a non-null pointer whose first field is lpCreateParams.
                const create_struct = std.math.add(u32, stack, 20) catch return false;
                const bytes = parentSlice(executor, create_struct, 48) orelse return false;
                for (window.create_fields, 0..) |field, index| {
                    const offset = index * 4;
                    const field_bytes: *[4]u8 = @ptrCast(bytes[offset..].ptr);
                    std.mem.writeInt(u32, field_bytes, field, .little);
                }
                callback_lparam = create_struct;
            }

            executor.raw_stop_eip = callback_return;
            executor.regs.pending_exception = 0;
            executor.mem.write32(stack, callback_return);
            executor.mem.write32(stack + 4, callback.window);
            executor.mem.write32(stack + 8, callback.message);
            executor.mem.write32(stack + 12, callback.wparam);
            executor.mem.write32(stack + 16, callback_lparam);
            executor.regs.esp = stack;
            executor.regs.eip = procedure;

            var returned = false;
            while (child.run_steps < maximum_steps and !executor.terminated) {
                if (executor.regs.eip == callback_return) {
                    returned = true;
                    break;
                }
                child.run_stopped_at = executor.regs.eip;
                if (!execution_engine.execNext(executor, thunks)) break;
                child.run_steps += 1;
            }

            executor.raw_stop_eip = saved_stop_eip;
            if (!returned) {
                if (windowTraceEnabled()) {
                    std.debug.print("PE32_WINDOW: WndProc failed msg=0x{X:0>4} eip=0x{X:0>8} exception=0x{X:0>8}\n", .{
                        callback.message,
                        executor.regs.eip,
                        executor.regs.pending_exception,
                    });
                }
                // Keep the failing callback's register/exception state visible
                // to the caller, and discard callbacks that could otherwise
                // repeatedly re-enter a broken WNDPROC on the next run.
                executor.pe32_window_callback = null;
                executor.pe32_window_callback_followup = null;
                return false;
            }

            executor.regs = saved_registers;
            if (windowTraceEnabled()) {
                std.debug.print("PE32_WINDOW: WndProc return msg=0x{X:0>4}\n", .{callback.message});
            }
            child.run_stopped_at = saved_registers.eip;
            child.active_window_message = 0;
            child.active_window_handle = 0;
            child.active_window_lparam = 0;
        }
        return true;
    }

    pub fn currentSummary(self: *const Runtime) Summary {
        const child = if (self.child) |*value| value else return .{};
        const executor = child.executor;
        return .{
            .child_created = true,
            .child_resumed = child.resumed,
            .dll_loaded = child.dll_image != null,
            .dll_attach_succeeded = child.dll_attach_succeeded,
            .dll_attach_steps = child.dll_attach_steps,
            .child_steps = child.run_steps,
            .child_terminated = child.executor.terminated,
            .child_exit_code = child.executor.exit_code,
            .stopped_at = child.run_stopped_at,
            .current_eip = executor.regs.eip,
            .eax = executor.regs.eax,
            .ebx = executor.regs.ebx,
            .ecx = executor.regs.ecx,
            .edx = executor.regs.edx,
            .esi = executor.regs.esi,
            .edi = executor.regs.edi,
            .ebp = executor.regs.ebp,
            .esp = executor.regs.esp,
            .eflags = executor.regs.flags.raw(),
            .pending_exception = executor.regs.pending_exception,
            .active_window_message = child.active_window_message,
            .active_window_handle = child.active_window_handle,
            .active_window_lparam = child.active_window_lparam,
            .ecx_0x50 = safeRead32(executor, executor.regs.ecx +% 0x50),
            .ecx_0x54 = safeRead32(executor, executor.regs.ecx +% 0x54),
            .stack_0 = safeRead32(executor, executor.regs.esp),
            .stack_4 = safeRead32(executor, executor.regs.esp +% 4),
            .stack_8 = safeRead32(executor, executor.regs.esp +% 8),
            .stack_12 = safeRead32(executor, executor.regs.esp +% 12),
        };
    }

    fn safeRead32(executor: *const Executor, address: u32) u32 {
        if (address < executor.mem.base) return 0;
        const offset: usize = @intCast(address - executor.mem.base);
        if (offset > executor.mem.data.len or 4 > executor.mem.data.len - offset) return 0;
        return std.mem.readInt(u32, executor.mem.data[offset..][0..4], .little);
    }

    fn argument(executor: *Executor, index: u32) u32 {
        return executor.mem.read32(executor.regs.esp + index * 4);
    }

    fn parentSlice(executor: *Executor, address: u32, length: usize) ?[]u8 {
        if (address < executor.mem.base) return null;
        const offset: usize = @intCast(address - executor.mem.base);
        if (offset > executor.mem.data.len or length > executor.mem.data.len - offset) return null;
        return executor.mem.data[offset .. offset + length];
    }

    fn guestCString(executor: *const Executor, address: u32, buffer: []u8) ?[]const u8 {
        if (address < executor.mem.base) return null;
        const offset: usize = @intCast(address - executor.mem.base);
        if (offset >= executor.mem.data.len) return null;
        var length: usize = 0;
        while (length < buffer.len and offset + length < executor.mem.data.len) : (length += 1) {
            const byte = executor.mem.data[offset + length];
            if (byte == 0) return buffer[0..length];
            buffer[length] = byte;
        }
        return null;
    }

    fn commandImageToken(command: []const u8) []const u8 {
        const trimmed = std.mem.trimStart(u8, command, " \t\r\n");
        if (trimmed.len == 0) return trimmed;
        if (trimmed[0] == '"') {
            const end = std.mem.indexOfScalar(u8, trimmed[1..], '"') orelse return trimmed[1..];
            return trimmed[1 .. end + 1];
        }
        const end = std.mem.indexOfAny(u8, trimmed, " \t\r\n") orelse trimmed.len;
        return trimmed[0..end];
    }

    fn normalizeWindowsPath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
        const normalized = try allocator.dupe(u8, raw);
        for (normalized) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
        return normalized;
    }

    fn resolveGuestPath(self: *Runtime, raw: []const u8) ![]u8 {
        const normalized = try normalizeWindowsPath(self.allocator, raw);
        defer self.allocator.free(normalized);
        if (std.fs.path.isAbsolute(normalized)) return self.allocator.dupe(u8, normalized);
        const parent_dir = std.fs.path.dirname(self.parent_image_path) orelse ".";
        const joined = try std.fs.path.join(self.allocator, &.{ parent_dir, normalized });
        defer self.allocator.free(joined);
        return std.fs.path.resolve(self.allocator, &.{joined});
    }

    fn createProcessA(self: *Runtime, parent: *Executor) u32 {
        self.create_process_calls += 1;
        if (self.child != null) {
            parent.win32_last_error = 87; // ERROR_INVALID_PARAMETER
            return 0;
        }

        const application_name_address = argument(parent, 0);
        const command_line_address = argument(parent, 1);
        const process_info_address = argument(parent, 9);
        if (process_info_address == 0 or parentSlice(parent, process_info_address, 16) == null) {
            parent.win32_last_error = 87;
            return 0;
        }

        var path_buffer: [4096]u8 = undefined;
        const command_line_text = if (command_line_address == 0) "" else guestCString(parent, command_line_address, &path_buffer) orelse {
            parent.win32_last_error = 87;
            return 0;
        };
        var app_buffer: [4096]u8 = undefined;
        const app_text = if (application_name_address == 0) null else guestCString(parent, application_name_address, &app_buffer) orelse {
            parent.win32_last_error = 87;
            return 0;
        };
        const raw_path = app_text orelse commandImageToken(command_line_text);
        if (raw_path.len == 0) {
            parent.win32_last_error = 87;
            return 0;
        }
        const child_path = self.resolveGuestPath(raw_path) catch {
            parent.win32_last_error = 2; // ERROR_FILE_NOT_FOUND
            return 0;
        };
        defer self.allocator.free(child_path);

        const image_bytes = std.Io.Dir.cwd().readFileAlloc(self.io, child_path, self.allocator, max_image_bytes) catch {
            parent.win32_last_error = 2; // ERROR_FILE_NOT_FOUND
            return 0;
        };
        const parsed_image = parser.parse(self.allocator, image_bytes) catch {
            self.allocator.free(image_bytes);
            parent.win32_last_error = 193; // ERROR_BAD_EXE_FORMAT
            return 0;
        };
        if (parsed_image.isPe32Plus() or parsed_image.machine != 0x014C or parsed_image.image_base != child_image_base) {
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 193;
            return 0;
        }
        var import_directory = imports.parseImportDirectory(self.allocator, image_bytes, &parsed_image) catch {
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 193;
            return 0;
        };

        const child_executor = self.allocator.create(Executor) catch {
            import_directory.deinit(self.allocator);
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
            return 0;
        };
        child_executor.* = Executor.init(self.allocator, child_memory_size);
        child_executor.setRawX86PeMode();
        child_executor.mem.base = child_memory_base;
        child_executor.pe32_main_module_base = child_image_base;
        child_executor.process_api_context = self;
        child_executor.process_api_handler = processApi;
        child_executor.pe32_window_host = self.window_host;
        win32_thunks.register_win32_console_thunks(child_executor);
        const mapped = image_loader.mapPreferredBase(child_executor, image_bytes, &parsed_image, child_image_base) catch {
            child_executor.deinit();
            self.allocator.destroy(child_executor);
            import_directory.deinit(self.allocator);
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 193;
            return 0;
        };

        const teb_size: u32 = 0x1000;
        const teb_base = child_image_base + parsed_image.size_of_image;
        const stack_base = teb_base + child_stack_reserve;
        child_executor.regs.eip = mapped.entry;
        child_executor.regs.esp = stack_base - 16;
        child_executor.regs.ebp = child_executor.regs.esp;
        child_executor.mem.stack_hint = child_executor.regs.esp;
        child_executor.regs.cs = 0x23;
        child_executor.regs.ds = 0x2B;
        child_executor.regs.ss = 0x2B;
        child_executor.regs.fs = 0x3B;
        child_executor.regs.fs_desc.base = teb_base;
        child_executor.regs.fs_desc.limit = teb_size - 1;
        child_executor.mem.write32(teb_base, std.math.maxInt(u32));
        child_executor.mem.write32(teb_base + 4, teb_base + teb_size);
        child_executor.mem.write32(teb_base + 8, stack_base);
        child_executor.mem.write32(teb_base + 0x18, teb_base);
        child_executor.mem.write32(teb_base + 0x20, 1);
        child_executor.mem.write32(teb_base + 0x24, 2);

        const built_command_line = command_line.build(self.allocator, child_path, &.{}) catch {
            child_executor.deinit();
            self.allocator.destroy(child_executor);
            import_directory.deinit(self.allocator);
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 8;
            return 0;
        };
        const owned_path = self.allocator.dupe(u8, child_path) catch {
            self.allocator.free(built_command_line);
            child_executor.deinit();
            self.allocator.destroy(child_executor);
            import_directory.deinit(self.allocator);
            self.allocator.free(parsed_image.sections);
            self.allocator.free(image_bytes);
            parent.win32_last_error = 8;
            return 0;
        };
        child_executor.pe32_image_path = owned_path;

        var child = Child{
            .executor = child_executor,
            .image = parsed_image,
            .image_bytes = image_bytes,
            .import_directory = import_directory,
            .image_path = owned_path,
            .command_line_bytes = built_command_line,
        };
        _ = child.addRegion(child_image_base, parsed_image.size_of_image);
        _ = child.addRegion(teb_base, child_stack_reserve);
        child_executor.pe32_command_line = child.command_line_bytes;

        for (child.import_directory.descriptors) |descriptor| {
            execution_engine.addIatEntryForExecutor(child_executor, child_image_base + descriptor.iat_rva, descriptor.function_name);
        }
        const creation_flags = argument(parent, 5);
        child.suspended = (creation_flags & 0x4) != 0; // CREATE_SUSPENDED
        child.resumed = !child.suspended;
        self.child = child;

        const process_info = parentSlice(parent, process_info_address, 16).?;
        std.mem.writeInt(u32, process_info[0..4], process_handle, .little);
        std.mem.writeInt(u32, process_info[4..8], main_thread_handle, .little);
        std.mem.writeInt(u32, process_info[8..12], 1, .little);
        std.mem.writeInt(u32, process_info[12..16], 2, .little);
        parent.win32_last_error = 0;
        return 1;
    }

    fn virtualAllocEx(self: *Runtime, parent: *Executor) u32 {
        self.virtual_alloc_calls += 1;
        const child = if (self.child) |*value| value else {
            parent.win32_last_error = 87;
            return 0;
        };
        if (argument(parent, 0) != process_handle) {
            parent.win32_last_error = 6; // ERROR_INVALID_HANDLE
            return 0;
        }
        const requested = argument(parent, 1);
        const size = argument(parent, 2);
        const allocation_type = argument(parent, 3);
        if (size == 0 or (allocation_type & 0x3000) != 0x3000) {
            parent.win32_last_error = 87;
            return 0;
        }
        const aligned_size_u64 = (@as(u64, size) + 0xFFF) & ~@as(u64, 0xFFF);
        if (aligned_size_u64 > std.math.maxInt(u32)) {
            parent.win32_last_error = 8;
            return 0;
        }
        const aligned_size: u32 = @intCast(aligned_size_u64);
        const base = if (requested == 0) blk: {
            const aligned_base = (child.allocation_cursor + 0xFFF) & ~@as(u32, 0xFFF);
            break :blk aligned_base;
        } else requested & ~@as(u32, 0xFFF);
        if (!child.addRegion(base, aligned_size)) {
            parent.win32_last_error = 8;
            return 0;
        }
        child.allocation_cursor = std.math.add(u32, base, aligned_size) catch {
            parent.win32_last_error = 8;
            return 0;
        };
        const offset: usize = @intCast(base - child.executor.mem.base);
        @memset(child.executor.mem.data[offset .. offset + aligned_size], 0);
        parent.win32_last_error = 0;
        return base;
    }

    fn virtualAlloc(self: *Runtime, executor: *Executor) u32 {
        const child = if (self.child) |*value| value else {
            executor.win32_last_error = 50; // ERROR_NOT_SUPPORTED outside the child model.
            return 0;
        };
        if (child.executor != executor) {
            executor.win32_last_error = 50;
            return 0;
        }

        const requested = argument(executor, 0);
        const size = argument(executor, 1);
        const allocation_type = argument(executor, 2);
        const allocation_flags = allocation_type & 0x3000;
        if (size == 0 or allocation_flags == 0) {
            executor.win32_last_error = 87; // ERROR_INVALID_PARAMETER
            return 0;
        }
        const rounded_size_u64 = (@as(u64, size) + 0xFFF) & ~@as(u64, 0xFFF);
        if (rounded_size_u64 > std.math.maxInt(u32)) {
            executor.win32_last_error = 8; // ERROR_NOT_ENOUGH_MEMORY
            return 0;
        }
        const rounded_size: u32 = @intCast(rounded_size_u64);
        const base = if (requested == 0) blk: {
            const aligned_base = (child.allocation_cursor + 0xFFF) & ~@as(u32, 0xFFF);
            break :blk aligned_base;
        } else requested & ~@as(u32, 0xFFF);

        // MEM_COMMIT may target an already reserved range. Treat that as a
        // commit within the child reservation; a fresh allocation still has
        // to claim a non-overlapping bounded region.
        if (allocation_flags == 0x1000 and requested != 0) {
            if (!child.regionContains(base, rounded_size)) {
                executor.win32_last_error = 8;
                return 0;
            }
        } else {
            if (!child.addRegion(base, rounded_size)) {
                executor.win32_last_error = 8;
                return 0;
            }
            child.allocation_cursor = std.math.add(u32, base, rounded_size) catch {
                executor.win32_last_error = 8;
                return 0;
            };
        }
        const offset: usize = @intCast(base - executor.mem.base);
        @memset(executor.mem.data[offset .. offset + rounded_size], 0);
        executor.win32_last_error = 0;
        return base;
    }

    fn virtualFree(self: *Runtime, executor: *Executor) u32 {
        const child = if (self.child) |*value| value else {
            executor.win32_last_error = 50;
            return 0;
        };
        if (child.executor != executor) {
            executor.win32_last_error = 50;
            return 0;
        }

        const address = argument(executor, 0);
        const size = argument(executor, 1);
        const free_type = argument(executor, 2);
        if ((free_type & 0x8000) != 0) { // MEM_RELEASE
            if (size != 0) {
                executor.win32_last_error = 87;
                return 0;
            }
            for (child.regions[0..child.region_count], 0..) |region, index| {
                if (region.base != address) continue;
                const offset: usize = @intCast(region.base - executor.mem.base);
                @memset(executor.mem.data[offset .. offset + region.size], 0);
                std.mem.copyForwards(Region, child.regions[index .. child.region_count - 1], child.regions[index + 1 .. child.region_count]);
                child.region_count -= 1;
                executor.win32_last_error = 0;
                return 1;
            }
            executor.win32_last_error = 487; // ERROR_INVALID_ADDRESS
            return 0;
        }
        if ((free_type & 0x4000) != 0) { // MEM_DECOMMIT
            const rounded_size_u64 = (@as(u64, size) + 0xFFF) & ~@as(u64, 0xFFF);
            if (size == 0 or rounded_size_u64 > std.math.maxInt(u32) or !child.regionContains(address, @intCast(rounded_size_u64))) {
                executor.win32_last_error = 487;
                return 0;
            }
            const offset: usize = @intCast(address - executor.mem.base);
            @memset(executor.mem.data[offset .. offset + @as(usize, @intCast(rounded_size_u64))], 0);
            executor.win32_last_error = 0;
            return 1;
        }
        executor.win32_last_error = 87;
        return 0;
    }

    fn writeProcessMemory(self: *Runtime, parent: *Executor) u32 {
        self.write_memory_calls += 1;
        const child = if (self.child) |*value| value else {
            parent.win32_last_error = 87;
            return 0;
        };
        if (argument(parent, 0) != process_handle) {
            parent.win32_last_error = 6;
            return 0;
        }
        const remote_address = argument(parent, 1);
        const local_address = argument(parent, 2);
        const size_u32 = argument(parent, 3);
        const size: usize = @intCast(size_u32);
        const source = parentSlice(parent, local_address, size) orelse {
            parent.win32_last_error = 998; // ERROR_NOACCESS
            return 0;
        };
        if (!child.regionContains(remote_address, size_u32) or remote_address < child.executor.mem.base) {
            parent.win32_last_error = 998;
            return 0;
        }
        const remote_offset: usize = @intCast(remote_address - child.executor.mem.base);
        @memcpy(child.executor.mem.data[remote_offset .. remote_offset + size], source);
        const written_address = argument(parent, 4);
        if (written_address != 0) {
            const written = parentSlice(parent, written_address, 4) orelse {
                parent.win32_last_error = 998;
                return 0;
            };
            std.mem.writeInt(u32, written[0..4], size_u32, .little);
        }
        parent.win32_last_error = 0;
        return 1;
    }

    fn createRemoteThread(self: *Runtime, parent: *Executor) u32 {
        self.remote_thread_calls += 1;
        const child = if (self.child) |*value| value else {
            parent.win32_last_error = 87;
            return 0;
        };
        if (argument(parent, 0) != process_handle or child.remote_thread_created) {
            parent.win32_last_error = 6;
            return 0;
        }
        const start_address = argument(parent, 3);
        const parameter = argument(parent, 4);
        const load_library = execution_engine.lookupIatFunctionPointer(parent, "LoadLibraryA") orelse {
            parent.win32_last_error = 127; // ERROR_PROC_NOT_FOUND
            return 0;
        };
        if (start_address != load_library) {
            parent.win32_last_error = 87;
            return 0;
        }
        var remote_path_buffer: [4096]u8 = undefined;
        const remote_path = guestCString(child.executor, parameter, &remote_path_buffer) orelse {
            parent.win32_last_error = 998;
            return 0;
        };
        if (!(self.loadDll(child, remote_path) catch false)) {
            parent.win32_last_error = 126; // ERROR_MOD_NOT_FOUND
            return 0;
        }
        child.remote_thread_created = true;
        child.remote_thread_finished = true;
        child.remote_thread_exit_code = child_dll_base;
        const thread_id_address = argument(parent, 6);
        if (thread_id_address != 0) {
            const out = parentSlice(parent, thread_id_address, 4) orelse {
                parent.win32_last_error = 998;
                return 0;
            };
            std.mem.writeInt(u32, out[0..4], 3, .little);
        }
        parent.win32_last_error = 0;
        return remote_thread_handle;
    }

    fn loadDll(self: *Runtime, child: *Child, raw_path: []const u8) anyerror!bool {
        const full_path = try self.resolveGuestPath(raw_path);
        errdefer self.allocator.free(full_path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(self.io, full_path, self.allocator, max_image_bytes);
        errdefer self.allocator.free(bytes);
        const image = try parser.parse(self.allocator, bytes);
        errdefer self.allocator.free(image.sections);
        if (image.isPe32Plus() or image.machine != 0x014C or image.image_base != child_dll_base) return error.UnsupportedDllLayout;
        var import_directory = try imports.parseImportDirectory(self.allocator, bytes, &image);
        errdefer import_directory.deinit(self.allocator);
        _ = try image_loader.mapPreferredBase(child.executor, bytes, &image, child_dll_base);
        if (!child.addRegion(child_dll_base, image.size_of_image)) return error.ChildAddressConflict;
        for (import_directory.descriptors) |descriptor| {
            execution_engine.addIatEntryForExecutor(child.executor, child_dll_base + descriptor.iat_rva, descriptor.function_name);
        }

        child.dll_path = full_path;
        child.dll_bytes = bytes;
        child.dll_image = image;
        child.dll_import_directory = import_directory;
        child.dll_attach_succeeded = self.runDllEntry(child, child_dll_base + image.entry_rva);
        return child.dll_attach_succeeded;
    }

    fn runDllEntry(self: *Runtime, child: *Child, entry: u32) bool {
        _ = self;
        const executor = child.executor;
        const saved_registers = executor.regs;
        const saved_stop_eip = executor.raw_stop_eip;
        executor.raw_stop_eip = dll_entry_return;
        defer executor.raw_stop_eip = saved_stop_eip;
        const stack = executor.regs.esp - 32;
        executor.mem.write32(stack, dll_entry_return);
        executor.mem.write32(stack + 4, child_dll_base);
        executor.mem.write32(stack + 8, 1); // DLL_PROCESS_ATTACH
        executor.mem.write32(stack + 12, 0);
        executor.regs.esp = stack;
        executor.regs.eip = entry;
        executor.regs.pending_exception = 0;
        var thunks = execution_engine.ThunkTable{};
        var steps: usize = 0;
        while (steps < 100_000 and !executor.terminated and executor.regs.eip != dll_entry_return) : (steps += 1) {
            if (!execution_engine.execNext(executor, &thunks)) break;
        }
        child.dll_attach_steps = steps;
        const returned = !executor.terminated and executor.regs.eip == dll_entry_return and executor.regs.eax != 0;
        executor.regs = saved_registers;
        return returned;
    }

    fn waitForSingleObject(self: *Runtime, parent: *Executor) u32 {
        self.wait_calls += 1;
        const handle = argument(parent, 0);
        if (handle == remote_thread_handle) {
            const child = if (self.child) |*value| value else {
                parent.win32_last_error = 6;
                return 0xFFFF_FFFF;
            };
            if (child.remote_thread_finished) return 0; // WAIT_OBJECT_0
        }
        parent.win32_last_error = if (handle == process_handle or handle == main_thread_handle) 0 else 6;
        return if (parent.win32_last_error == 0) 0 else 0xFFFF_FFFF;
    }

    fn getExitCodeThread(self: *Runtime, parent: *Executor) u32 {
        const handle = argument(parent, 0);
        const output_address = argument(parent, 1);
        if (handle != remote_thread_handle) {
            parent.win32_last_error = 6;
            return 0;
        }
        const child = if (self.child) |*value| value else {
            parent.win32_last_error = 6;
            return 0;
        };
        const output = parentSlice(parent, output_address, 4) orelse {
            parent.win32_last_error = 998;
            return 0;
        };
        std.mem.writeInt(u32, output[0..4], child.remote_thread_exit_code, .little);
        parent.win32_last_error = 0;
        return 1;
    }

    fn resumeThread(self: *Runtime, parent: *Executor) u32 {
        self.resume_calls += 1;
        if (argument(parent, 0) != main_thread_handle) {
            parent.win32_last_error = 6;
            return std.math.maxInt(u32);
        }
        const child = if (self.child) |*value| value else {
            parent.win32_last_error = 6;
            return std.math.maxInt(u32);
        };
        parent.win32_last_error = 0;
        if (!child.suspended) return 0;
        child.suspended = false;
        child.resumed = true;
        return 1;
    }

    fn closeHandle(self: *Runtime, parent: *Executor) u32 {
        _ = self;
        const handle = argument(parent, 0);
        if (handle == process_handle or handle == main_thread_handle or handle == remote_thread_handle) {
            parent.win32_last_error = 0;
            return 1;
        }
        parent.win32_last_error = 6;
        return 0;
    }

    fn virtualProtect(self: *Runtime, executor: *Executor) u32 {
        _ = self;
        const address = argument(executor, 0);
        const size = argument(executor, 1);
        const old_protect_address = argument(executor, 3);
        if (address < executor.mem.base or size == 0) {
            executor.win32_last_error = 998;
            return 0;
        }
        const offset: usize = @intCast(address - executor.mem.base);
        if (offset > executor.mem.data.len or size > executor.mem.data.len - offset) {
            executor.win32_last_error = 998;
            return 0;
        }
        if (old_protect_address != 0) {
            const old = parentSlice(executor, old_protect_address, 4) orelse {
                executor.win32_last_error = 998;
                return 0;
            };
            // The PE runner currently has a flat RWX backing store and does
            // not enforce page permissions. Report that effective policy.
            std.mem.writeInt(u32, old[0..4], 0x40, .little);
        }
        executor.win32_last_error = 0;
        return 1;
    }
};

test "CreateProcess command-line token extraction respects quoted paths" {
    try std.testing.expectEqualStrings("/Games/Maze Game/ssmaze.scr", Runtime.commandImageToken("\"/Games/Maze Game/ssmaze.scr\" /s"));
    try std.testing.expectEqualStrings("ssmaze.scr", Runtime.commandImageToken("ssmaze.scr /s"));
}

test "process memory helpers reject addresses outside the owning executor" {
    var executor = Executor.init(std.testing.allocator, 0x1000);
    defer executor.deinit();
    executor.mem.base = 0x0040_0000;
    try std.testing.expect(Runtime.parentSlice(&executor, 0x0040_0FF0, 16) != null);
    try std.testing.expect(Runtime.parentSlice(&executor, 0x0040_0FF1, 16) == null);
    try std.testing.expect(Runtime.parentSlice(&executor, 0x003F_FFFF, 1) == null);
}

test "VirtualAlloc commits inside a child reservation and VirtualFree releases it" {
    const allocator = std.testing.allocator;
    const executor = try allocator.create(Executor);
    executor.* = Executor.init(allocator, child_memory_size);
    executor.setRawX86PeMode();
    executor.mem.base = child_memory_base;

    var child = Child{
        .executor = executor,
        .image = .{
            .pe_offset = 0,
            .machine = 0x014C,
            .coff_characteristics = 0,
            .optional_header_kind = .pe32,
            .optional_header_size = 0,
            .entry_rva = 0,
            .image_base = child_image_base,
            .subsystem = 0,
            .dll_characteristics = 0,
            .section_alignment = 0x1000,
            .file_alignment = 0x200,
            .size_of_image = 0,
            .size_of_headers = 0,
            .size_of_stack_reserve = 0,
            .size_of_stack_commit = 0,
            .size_of_heap_reserve = 0,
            .size_of_heap_commit = 0,
            .number_of_rva_and_sizes = 0,
            .data_directories = [_]parser.DataDirectory{.{}} ** parser.data_directory_count,
            .number_of_sections = 0,
            .sections = try allocator.alloc(parser.Section, 0),
        },
        .image_bytes = try allocator.alloc(u8, 0),
        .import_directory = .{ .descriptors = &.{}, .pointer_size = 4 },
        .image_path = try allocator.dupe(u8, "child.exe"),
        .command_line_bytes = try allocator.alloc(u8, 0),
    };
    var runtime = Runtime{ .allocator = allocator, .io = undefined, .parent_image_path = "loader.exe", .child = child };
    defer runtime.deinit();
    child = undefined;

    const stack = child_memory_base + 0x1000;
    executor.regs.esp = stack;
    executor.mem.write32(stack, 0);
    executor.mem.write32(stack + 4, 0x400000);
    executor.mem.write32(stack + 8, 0x2000); // MEM_RESERVE
    executor.mem.write32(stack + 12, 4); // PAGE_READWRITE
    const reservation = runtime.virtualAlloc(executor);
    try std.testing.expectEqual(remote_alloc_base, reservation);
    try std.testing.expectEqual(@as(usize, 1), runtime.child.?.region_count);

    executor.mem.write32(stack, reservation + 0x1000);
    executor.mem.write32(stack + 4, 0x1000);
    executor.mem.write32(stack + 8, 0x1000); // MEM_COMMIT within the reservation
    executor.mem.write32(stack + 12, 4);
    try std.testing.expectEqual(reservation + 0x1000, runtime.virtualAlloc(executor));

    executor.mem.write8(reservation + 0x1000, 0xA5);
    executor.mem.write32(stack, reservation);
    executor.mem.write32(stack + 4, 0);
    executor.mem.write32(stack + 8, 0x8000); // MEM_RELEASE
    try std.testing.expectEqual(@as(u32, 1), runtime.virtualFree(executor));
    try std.testing.expectEqual(@as(usize, 0), runtime.child.?.region_count);
    try std.testing.expectEqual(@as(u8, 0), executor.mem.read8(reservation + 0x1000));
}
