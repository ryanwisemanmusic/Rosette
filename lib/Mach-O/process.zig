const std = @import("std");
const macho = @import("macho.zig");
const fat = @import("fat.zig");
const x64_decoder = @import("x64_decoder");
const x64_interpreter = @import("x64_interpreter");
const macho_runtime = @import("macho_runtime");
const exit_diagnostics = @import("exit_diagnostics");
const macho_metadata = @import("metadata.zig");
const compat_runtime = @import("macho_compat_runtime");
const import_resolution = @import("resolution/import_engine.zig");
const initialization_resolution = @import("resolution/initialization_engine.zig");
const memory_transaction = @import("resolution/memory_transaction.zig");
const dynamic_library_forwarder = @import("resolution/dynamic_library_forwarder.zig");
const smart_stub_generator = @import("resolution/smart_stub_generator.zig");
const cxx_exception_diagnostics = @import("resolution/cxx_exception_diagnostics.zig");
const fs_io_forwarder = @import("resolution/fs_io_forwarder.zig");
const memory_management_forwarder = @import("resolution/memory_management_forwarder.zig");
const launch_argument_accelerator = @import("resolution/launch_argument_accelerator.zig");
const startup_observer = @import("resolution/startup_observer.zig");
const itanium_unwinder = @import("resolution/itanium_unwinder.zig");
const itanium_dynamic_cast = @import("resolution/itanium_dynamic_cast.zig");
const libcpp_filesystem = @import("resolution/libcpp_filesystem.zig");
const libcpp_stream_bridge = @import("resolution/libcpp_stream_bridge.zig");
const logging_runtime = @import("resolution/logging_runtime.zig");
const pthread_runtime = @import("resolution/pthread_runtime.zig");
const diagnostic_text_accelerator = @import("resolution/diagnostic_text_accelerator.zig");
const contract = @import("contract");

const log = std.log.scoped(.macho);

const Regs = x64_decoder.Regs;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;
const BitScanKind = x64_decoder.BitScanKind;
const bitScan = x64_decoder.bitScan;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const RFL_DF: u32 = 1 << 10;

const STACK_SIZE: u64 = 8 * 1024 * 1024;
const MEM_SIZE: u64 = 512 * 1024 * 1024;
const MEM_BASE: u64 = 0x0;
const PAGE_SIZE: u64 = 4096;
const TRACE_BUFFER_LEN: usize = 256;
const IMPORT_TRACE_BUFFER_LEN: usize = 64;
const STUB_ENTRY_SIZE: u64 = 10;
const UNSUPPORTED_RUNTIME_EXIT_CODE: u64 = 125;
const GUEST_FILE_BASE: u64 = 0xFFFF_FF10_0000_0000;
const GUEST_FILE_MAX: usize = 32;
const BOUND_IMPORT_THUNK_BASE: u64 = 0xFFFF_FC00_0000_0000;
const BOUND_IMPORT_THUNK_STRIDE: u64 = 16;
const INITIALIZER_RETURN_SENTINEL: u64 = 0xFFFF_FB00_0000_0000;
const INITIALIZER_STEP_LIMIT: u64 = 2_000_000;
const GUEST_LOG_BUFFER_SIZE: u64 = 64 * 1024;
const DECODE_CACHE_ENTRY_COUNT: usize = 1 << 16;
const DECODE_CACHE_HASH_SHIFT: u6 = 48;

const MachSegment = macho.MachSegment;

const TraceEntry = struct {
    rip: u64 = 0,
    op: Op = .invalid,
    len: u8 = 0,
    rsp: u64 = 0,
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
};

const ImportTraceEntry = struct {
    symbol: []const u8 = "",
    dylib: []const u8 = "",
    stub_address: u64 = 0,
    return_address: u64 = 0,
    synthetic_result: u64 = 0,
    caller_symbol: []const u8 = "",
    caller_offset: u64 = 0,
};

const ControlTransferContext = struct {
    kind: []const u8,
    instruction_address: u64,
    operand_address: u64 = 0,
    target_address: u64,
    return_address: u64 = 0,
};

const DecodeCacheEntry = struct {
    rip: u64 = std.math.maxInt(u64),
    code_generation: u64 = 0,
    decoded: DecodedInsn = .{},
};

const ImportHandlerResult = union(enum) {
    handled: u64,
    handled_void,
    control_transferred,
    unsupported: u64,
    terminated: u64,
};

const InitializerRunOutcome = enum {
    completed,
    deferred,
    failed,
};

const GuestFileKind = enum {
    regular,
    stdout,
    stderr,
};

const GuestFile = struct {
    active: bool = false,
    fd: i32 = -1,
    position: i64 = 0,
    error_flag: bool = false,
    kind: GuestFileKind = .regular,
};

const BoundImportThunk = struct {
    address: u64,
    name: []const u8,
    dylib: []const u8,
};

const InternalCompatibilityTargets = struct {
    cxxopts_split_option_names: u64 = 0,
    parse_launch_arguments: u64 = 0,
    initialize_logging: u64 = 0,
    shutdown_logging: u64 = 0,
    cvar_add_to_launch_options: [32]u64 = [_]u64{0} ** 32,
    cvar_add_to_launch_options_count: usize = 0,
    guest_log_get_thread_buffer: u64 = 0,
    guest_log_append_formatted: u64 = 0,
    guest_log_append_view: u64 = 0,
    libcxx_basic_streambuf_pubsetbuf: u64 = 0,
    print_config_to_log: u64 = 0,
};

const InitializerCheckpoint = struct {
    heap_next: u64,
    compat: compat_runtime.Runtime,
    monotonic_nanoseconds: u64,
    ios_xalloc_next: u64,
    cxxopts_split_accelerations: u64,
    guest_errno_address: u64,
};

pub const MachOState = struct {
    allocator: std.mem.Allocator,
    mem: []u8,
    mem_base: u64,
    mem_size: u64,
    heap_next: u64,
    regs: Regs = .{},
    xmm: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    ymm_hi: [16][16]u8 = [_][16]u8{[_]u8{0} ** 16} ** 16,
    cpu_profile: x64_decoder.capabilities.Profile = .xenia,
    compat: compat_runtime.Runtime = .{},
    terminated: bool = false,
    exit_code: u64 = 0,
    faulted: bool = false,
    termination_reason: u8 = @intFromEnum(exit_diagnostics.TerminationReason.unknown),
    data: []const u8,
    segments: []const MachSegment,
    metadata: macho_metadata.Metadata,
    entry_point_vaddr: u64 = 0,
    stack_size: u64 = 0,
    guest_fds: [16]i32 = .{-1} ** 16,
    next_guest_fd: u64 = 3,
    monotonic_nanoseconds: u64 = 1_000_000_000,
    ios_xalloc_next: u64 = 4,
    verbose_trace: bool = false,
    contract_verification: bool = false,
    max_steps: u64 = 100_000_000,
    guest_assertion_count: u64 = 0,
    initializer_abort_requested: bool = false,
    cxxopts_split_accelerations: u64 = 0,
    positional_options_captured: bool = false,
    executed_steps: u64 = 0,
    internal_targets: InternalCompatibilityTargets = .{},
    launch_options: launch_argument_accelerator.Filter = .{},
    startup: startup_observer.Observer = .{},
    guest_errno_address: u64 = 0,
    guest_stdin_pointer_address: u64 = 0,
    guest_stdout_pointer_address: u64 = 0,
    guest_stderr_pointer_address: u64 = 0,
    guest_log_buffer_address: u64 = 0,
    guest_log_mirror_fd: i32 = -1,
    guest_log_line_count: u64 = 0,
    strict_initializers: bool = false,
    strict_imports: bool = false,
    import_resolver: import_resolution.Engine,
    initializer_resolver: initialization_resolution.Engine,
    dynamic_forwarder: dynamic_library_forwarder.Forwarder = .{},
    fs_forwarder: fs_io_forwarder.Forwarder,
    libcxx_filesystem: libcpp_filesystem.Bridge = .{},
    libcxx_streams: libcpp_stream_bridge.Bridge = .{},
    logging: logging_runtime.Engine = .{},
    pthreads: pthread_runtime.Runtime = .{},
    diagnostic_text: diagnostic_text_accelerator.Engine = .{},
    memory_forwarder: memory_management_forwarder.Manager,
    smart_stubs: smart_stub_generator.Generator = .{},
    cxx_exceptions: cxx_exception_diagnostics.Tracker = .{},
    unwinder: itanium_unwinder.Engine = .{},
    dynamic_casts: itanium_dynamic_cast.Engine = .{},
    last_unwind_inspection: ?itanium_unwinder.Inspection = null,
    import_provider_override: ?import_resolution.Provider = null,
    import_confidence_override: ?import_resolution.Confidence = null,
    initializer_memory: memory_transaction.Journal,
    initializer_checkpoint: ?InitializerCheckpoint = null,
    trace_entries: [TRACE_BUFFER_LEN]TraceEntry = [_]TraceEntry{TraceEntry{}} ** TRACE_BUFFER_LEN,
    trace_index: usize = 0,
    trace_filled: bool = false,
    trace_range_start: ?u64 = null,
    trace_range_end: ?u64 = null,
    pending_stub_slot: ?u32 = null,
    pending_stub_entry_rip: ?u64 = null,
    pending_import_stub_rip: ?u64 = null,
    helper_cluster_start: ?u64 = null,
    helper_cluster_end: ?u64 = null,
    import_trace_entries: [IMPORT_TRACE_BUFFER_LEN]ImportTraceEntry = [_]ImportTraceEntry{ImportTraceEntry{}} ** IMPORT_TRACE_BUFFER_LEN,
    import_trace_index: usize = 0,
    import_trace_filled: bool = false,
    unresolved_import_count: u64 = 0,
    pending_control_transfer: ?ControlTransferContext = null,
    terminal_control_transfer: ?exit_diagnostics.ControlTransferFailure = null,
    guest_files: [GUEST_FILE_MAX]GuestFile = [_]GuestFile{GuestFile{}} ** GUEST_FILE_MAX,
    bound_import_thunks: []BoundImportThunk = &.{},
    decode_cache: []DecodeCacheEntry,
    decode_cache_hits: u64 = 0,
    decode_cache_misses: u64 = 0,
    code_generation: u64 = 1,
    mapped_min: u64,
    executable_min: u64,
    executable_max: u64,

    pub fn init(allocator: std.mem.Allocator, binary_data: []const u8) !MachOState {
        var state = try macho.load(allocator, binary_data);
        errdefer state.deinit();
        var metadata = try macho_metadata.Metadata.init(allocator, binary_data);
        errdefer metadata.deinit();

        var min_vaddr: u64 = std.math.maxInt(u64);
        var max_vaddr: u64 = 0;
        var mapped_min: u64 = std.math.maxInt(u64);
        var executable_min: u64 = std.math.maxInt(u64);
        var executable_max: u64 = 0;

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            if (seg.vmaddr < min_vaddr) min_vaddr = seg.vmaddr;
            const seg_end = try std.math.add(u64, seg.vmaddr, seg.vmsize);
            if (seg_end > max_vaddr) max_vaddr = seg_end;
            if (seg.initprot != 0) mapped_min = @min(mapped_min, seg.vmaddr);
            if (seg.initprot & 0x04 != 0) {
                executable_min = @min(executable_min, seg.vmaddr);
                executable_max = @max(executable_max, seg_end);
            }
        }

        if (min_vaddr == std.math.maxInt(u64)) return error.NoLoadableSegments;

        const image_base = alignDown(min_vaddr, PAGE_SIZE);
        const image_end = alignUp(max_vaddr, PAGE_SIZE) catch return error.SegmentOverflow;
        const image_size = image_end - image_base;

        const required_mem = image_size + STACK_SIZE;
        const mem_size_aligned = alignUp(required_mem, PAGE_SIZE) catch MEM_SIZE;
        const final_mem_size = @max(mem_size_aligned, MEM_SIZE);

        const mem = try allocator.alloc(u8, @intCast(final_mem_size));
        @memset(mem, 0);

        for (state.segments) |seg| {
            if (seg.vmsize == 0) continue;
            const off = (seg.vmaddr -| image_base);
            if (off + seg.vmsize > final_mem_size) continue;
            const copy_size = @min(seg.filesize, seg.vmsize);
            if (copy_size > 0) {
                const file_off = seg.fileoff;
                if (file_off + copy_size <= binary_data.len) {
                    @memcpy(mem[off..][0..@as(usize, @intCast(copy_size))], binary_data[file_off..][0..@as(usize, @intCast(copy_size))]);
                }
            }
        }

        var entry_vaddr: u64 = state.entry_point;
        if (state.entry_point > 0) {
            var mapped_entry: ?u64 = null;
            for (state.segments) |seg| {
                const file_range_end = seg.fileoff + seg.filesize;
                if (state.entry_point >= seg.fileoff and state.entry_point < file_range_end) {
                    mapped_entry = seg.vmaddr + (state.entry_point - seg.fileoff);
                    break;
                }
            }
            if (mapped_entry) |resolved| {
                entry_vaddr = resolved;
            } else if (state.entry_point < image_size) {
                entry_vaddr = image_base + state.entry_point;
            }
        }

        const initializer_count = metadata.initializer_addresses.len;
        const decode_cache = try allocator.alloc(DecodeCacheEntry, DECODE_CACHE_ENTRY_COUNT);
        @memset(decode_cache, .{});
        var result = MachOState{
            .allocator = allocator,
            .mem = mem,
            .mem_base = image_base,
            .mem_size = final_mem_size,
            .heap_next = image_end,
            .data = binary_data,
            .segments = try allocator.dupe(MachSegment, state.segments),
            .metadata = metadata,
            .entry_point_vaddr = entry_vaddr,
            .stack_size = if (state.stack_size > 0) state.stack_size else STACK_SIZE,
            .import_resolver = import_resolution.Engine.init(allocator),
            .initializer_resolver = initialization_resolution.Engine.init(allocator, initializer_count),
            .initializer_memory = memory_transaction.Journal.init(allocator, PAGE_SIZE),
            .fs_forwarder = fs_io_forwarder.Forwarder.init(allocator),
            .memory_forwarder = memory_management_forwarder.Manager.init(allocator),
            .decode_cache = decode_cache,
            .mapped_min = mapped_min,
            .executable_min = executable_min,
            .executable_max = executable_max,
        };
        result.guest_files[0] = .{ .active = true, .fd = 0, .kind = .regular };
        result.guest_files[1] = .{ .active = true, .fd = 1, .kind = .stdout };
        result.guest_files[2] = .{ .active = true, .fd = 2, .kind = .stderr };
        result.internal_targets.cxxopts_split_option_names = result.metadata.symbolAddressWithPrefix(
            "__ZN7cxxopts6values11parser_tool18split_option_names",
        ) orelse 0;
        result.internal_targets.parse_launch_arguments = result.metadata.symbolAddressWithPrefix(
            "__ZN4cvar20ParseLaunchArguments",
        ) orelse 0;
        result.internal_targets.initialize_logging = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe17InitializeLogging",
        ) orelse 0;
        result.internal_targets.shutdown_logging = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe15ShutdownLoggingEv",
        ) orelse 0;
        result.internal_targets.cvar_add_to_launch_options_count = result.metadata.symbolAddressesMatching(
            "__ZN4cvar",
            "AddToLaunchOptions",
            &result.internal_targets.cvar_add_to_launch_options,
        );
        result.internal_targets.guest_log_get_thread_buffer = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging8internal15GetThreadBufferEv",
        ) orelse 0;
        result.internal_targets.guest_log_append_formatted = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging8internal13AppendLogLineENS_8LogLevelEcm",
        ) orelse 0;
        result.internal_targets.guest_log_append_view = result.metadata.symbolAddressWithPrefix(
            "__ZN2xe7logging13AppendLogLineENS_8LogLevelEc",
        ) orelse 0;
        result.internal_targets.libcxx_basic_streambuf_pubsetbuf = result.metadata.symbolAddressWithPrefix(
            "__ZNSt3__115basic_streambufIcNS_11char_traitsIcEEE9pubsetbuf",
        ) orelse 0;
        result.internal_targets.print_config_to_log = result.metadata.symbolAddressWithPrefix(
            "__ZN6config16PrintConfigToLog",
        ) orelse 0;
        result.logging.configure(
            result.internal_targets.guest_log_get_thread_buffer != 0,
            result.internal_targets.guest_log_append_formatted != 0,
            result.internal_targets.guest_log_append_view != 0,
        );
        result.unwinder.configure(&result.metadata);
        result.applyDyldBindings() catch |err| {
            log.warn("dyld data binding setup failed: {s}", .{@errorName(err)});
        };
        return result;
    }

    pub fn deinit(self: *MachOState) void {
        self.closeGuestFiles();
        self.libcxx_streams.deinit();
        self.import_resolver.deinit();
        self.initializer_resolver.deinit();
        self.dynamic_forwarder.deinit();
        self.fs_forwarder.deinit();
        self.memory_forwarder.deinit();
        self.initializer_memory.deinit();
        self.allocator.free(self.decode_cache);
        if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
        self.metadata.deinit();
        self.allocator.free(self.mem);
        self.allocator.free(self.segments);
        if (self.bound_import_thunks.len != 0) self.allocator.free(self.bound_import_thunks);
    }

    fn applyDyldBindings(self: *MachOState) !void {
        var stubs = std.StringHashMap(u64).init(self.allocator);
        defer stubs.deinit();
        for (self.metadata.imports) |imported| {
            try stubs.put(imported.name, imported.stub_address);
        }

        var thunk_addresses = std.StringHashMap(u64).init(self.allocator);
        defer thunk_addresses.deinit();
        var thunks: std.ArrayList(BoundImportThunk) = .empty;
        errdefer thunks.deinit(self.allocator);

        var applied: usize = 0;
        var callable_got_bindings: usize = 0;
        var stack_guard_address: u64 = 0;
        for (self.metadata.bindings) |binding| {
            if (std.mem.eql(u8, binding.name, "___stdinp") or
                std.mem.eql(u8, binding.name, "___stdoutp") or
                std.mem.eql(u8, binding.name, "___stderrp"))
            {
                const pointer_address = self.standardStreamPointer(binding.name) orelse continue;
                if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
                self.write64(binding.address, pointer_address);
                applied += 1;
                continue;
            }
            if (std.mem.eql(u8, binding.name, "___stack_chk_guard")) {
                if (stack_guard_address == 0) {
                    stack_guard_address = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse continue;
                    self.write64(stack_guard_address, 0x9E37_79B9_7F4A_7C15);
                }
                if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
                self.write64(binding.address, stack_guard_address);
                applied += 1;
                continue;
            }
            const section = self.metadata.sectionAtAddress(binding.address) orelse continue;
            if (!isCallableConstantBinding(section, binding.name, stubs.contains(binding.name))) continue;
            const destination = self.guestMemory(binding.address, @sizeOf(u64)) orelse continue;
            const existing = std.mem.readInt(u64, destination[0..8], .little);
            if (std.mem.eql(u8, binding.dylib, "weak-lookup") and existing != 0) continue;
            const force_bound_thunk = bindingRequiresBoundThunk(section);
            var target = if (!force_bound_thunk) stubs.get(binding.name) orelse 0 else 0;
            if (target == 0) target = blk: {
                if (thunk_addresses.get(binding.name)) |existing_thunk| break :blk existing_thunk;
                const thunk_address = BOUND_IMPORT_THUNK_BASE + @as(u64, @intCast(thunks.items.len)) * BOUND_IMPORT_THUNK_STRIDE;
                try thunks.append(self.allocator, .{
                    .address = thunk_address,
                    .name = binding.name,
                    .dylib = binding.dylib,
                });
                try thunk_addresses.put(binding.name, thunk_address);
                break :blk thunk_address;
            };
            if (binding.addend > 0 and target < BOUND_IMPORT_THUNK_BASE) {
                target +%= @intCast(binding.addend);
            } else if (binding.addend < 0 and target < BOUND_IMPORT_THUNK_BASE) {
                target -%= @intCast(-binding.addend);
            }
            std.mem.writeInt(u64, destination[0..8], target, .little);
            applied += 1;
            if (std.mem.eql(u8, section.name, "__got")) callable_got_bindings += 1;
        }

        self.bound_import_thunks = try thunks.toOwnedSlice(self.allocator);
        std.debug.print(
            "macho-processor: applied {d} dyld data binding(s), including {d} callable GOT pointer(s); created {d} synthetic import thunk(s)\n",
            .{ applied, callable_got_bindings, self.bound_import_thunks.len },
        );
    }

    fn isCallableConstantBinding(
        section: macho_metadata.Section,
        symbol_name: []const u8,
        has_import_stub: bool,
    ) bool {
        if (std.mem.eql(u8, section.name, "__got")) return has_import_stub;
        if (!std.mem.eql(u8, section.name, "__const")) return false;
        if (has_import_stub) return true;
        if (!std.mem.startsWith(u8, symbol_name, "__Z")) return false;

        const abi_data_symbols = [_][]const u8{
            "__ZGV", "__ZGR", "__ZTC", "__ZTI", "__ZTS", "__ZTT", "__ZTV",
        };
        for (abi_data_symbols) |prefix| {
            if (std.mem.startsWith(u8, symbol_name, prefix)) return false;
        }
        return true;
    }

    fn bindingRequiresBoundThunk(section: macho_metadata.Section) bool {
        return std.mem.eql(u8, section.name, "__got");
    }

    pub fn addrToOffset(self: *const MachOState, vaddr: u64) ?u64 {
        return mappedOffset(self.mem_base, self.mem_size, self.mapped_min, vaddr);
    }

    fn isExecutableAddress(self: *const MachOState, address: u64) bool {
        for (self.segments) |segment| {
            if (segment.initprot & 0x04 == 0) continue;
            if (address >= segment.vmaddr and address < segment.vmaddr + segment.vmsize) return true;
        }
        return false;
    }

    fn diagnosticSymbol(self: *const MachOState, address: u64) ?exit_diagnostics.SymbolizedAddress {
        if (address == 0) return null;
        const symbol = self.metadata.nearestSymbol(address) orelse return null;
        return .{
            .address = address,
            .symbol = symbol.name,
            .symbol_offset = symbol.offset,
        };
    }

    pub fn read8(self: *const MachOState, vaddr: u64) u8 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        return self.mem[off];
    }

    pub fn read16(self: *const MachOState, vaddr: u64) u16 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 2 > self.mem.len) return 0;
        return std.mem.readInt(u16, self.mem[off..][0..2], .little);
    }

    pub fn read32(self: *const MachOState, vaddr: u64) u32 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 4 > self.mem.len) return 0;
        return std.mem.readInt(u32, self.mem[off..][0..4], .little);
    }

    pub fn read64(self: *const MachOState, vaddr: u64) u64 {
        const off = self.addrToOffset(vaddr) orelse return 0;
        if (off + 8 > self.mem.len) return 0;
        return std.mem.readInt(u64, self.mem[off..][0..8], .little);
    }

    pub fn write8(self: *MachOState, vaddr: u64, val: u8) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off < self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 1);
            self.noteGuestWrite(vaddr, 1);
            self.mem[off] = val;
        }
    }

    pub fn write16(self: *MachOState, vaddr: u64, val: u16) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 2 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 2);
            self.noteGuestWrite(vaddr, 2);
            std.mem.writeInt(u16, self.mem[off..][0..2], val, .little);
        }
    }

    pub fn write32(self: *MachOState, vaddr: u64, val: u32) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 4 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 4);
            self.noteGuestWrite(vaddr, 4);
            std.mem.writeInt(u32, self.mem[off..][0..4], val, .little);
        }
    }

    pub fn write64(self: *MachOState, vaddr: u64, val: u64) void {
        const off = self.addrToOffset(vaddr) orelse return;
        if (off + 8 <= self.mem.len) {
            self.initializer_memory.capture(self.mem, @intCast(off), 8);
            self.noteGuestWrite(vaddr, 8);
            std.mem.writeInt(u64, self.mem[off..][0..8], val, .little);
        }
    }

    pub fn push(self: *MachOState, val: u64) void {
        self.regs.rsp -|= 8;
        self.write64(self.regs.rsp, val);
    }

    pub fn pop(self: *MachOState) u64 {
        const val = self.read64(self.regs.rsp);
        self.regs.rsp +|= 8;
        return val;
    }

    pub fn readMemVal(self: *MachOState, addr: u64, size: Size) u64 {
        return switch (size) {
            .bits8 => self.read8(addr),
            .bits16 => self.read16(addr),
            .bits32 => self.read32(addr),
            .bits64 => self.read64(addr),
        };
    }

    pub fn writeMemVal(self: *MachOState, addr: u64, size: Size, val: u64) void {
        switch (size) {
            .bits8 => self.write8(addr, @intCast(val & 0xFF)),
            .bits16 => self.write16(addr, @intCast(val & 0xFFFF)),
            .bits32 => self.write32(addr, @intCast(val & 0xFFFFFFFF)),
            .bits64 => self.write64(addr, val),
        }
    }

    pub fn readMem128(self: *const MachOState, addr: u64) [16]u8 {
        var value = [_]u8{0} ** 16;
        const off = self.addrToOffset(addr) orelse return value;
        if (off + 16 > self.mem.len) return value;
        @memcpy(value[0..], self.mem[off..][0..16]);
        return value;
    }

    pub fn writeMem128(self: *MachOState, addr: u64, value: [16]u8) void {
        const off = self.addrToOffset(addr) orelse return;
        if (off + 16 > self.mem.len) return;
        self.initializer_memory.capture(self.mem, @intCast(off), 16);
        self.noteGuestWrite(addr, 16);
        @memcpy(self.mem[off..][0..16], value[0..]);
    }

    pub fn guestMemory(self: *MachOState, addr: u64, count: u64) ?[]u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        self.initializer_memory.capture(self.mem, off_usize, count_usize);
        self.noteGuestWrite(addr, count);
        return self.mem[off_usize .. off_usize + count_usize];
    }

    fn noteGuestWrite(self: *MachOState, address: u64, count: u64) void {
        if (count == 0 or self.executable_min == std.math.maxInt(u64)) return;
        const end = address +| count;
        if (address < self.executable_max and end > self.executable_min) {
            self.code_generation +%= 1;
            if (self.code_generation == 0) self.code_generation = 1;
        }
    }

    pub fn guestMemoryConst(self: *const MachOState, addr: u64, count: u64) ?[]const u8 {
        if (count > std.math.maxInt(usize)) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        const count_usize: usize = @intCast(count);
        if (off_usize > self.mem.len or count_usize > self.mem.len - off_usize) return null;
        return self.mem[off_usize .. off_usize + count_usize];
    }

    pub fn guestAlloc(self: *MachOState, requested_size: u64, alignment: u64) ?u64 {
        const size = @max(requested_size, 1);
        const mask = alignment - 1;
        const start = (self.heap_next + mask) & ~mask;
        const end = std.math.add(u64, start, size) catch return null;
        const stack_floor = self.mem_base + self.mem_size -| self.stack_size;
        if (end > stack_floor) return null;
        const storage = self.guestMemory(start, size) orelse return null;
        @memset(storage, 0);
        self.heap_next = end;
        return start;
    }

    pub fn guestHeapAllocate(self: *MachOState, size: u64, alignment: u64) ?u64 {
        return self.memory_forwarder.allocate(self, size, alignment);
    }

    pub fn guestHeapRelease(self: *MachOState, address: u64) void {
        self.memory_forwarder.release(address);
    }

    pub fn guestHeapContains(self: *const MachOState, address: u64) bool {
        return self.memory_forwarder.allocationSize(address) != null;
    }

    pub fn guestCString(self: *const MachOState, addr: u64, max_len: usize) ?[]const u8 {
        if (addr == 0) return null;
        const off = self.addrToOffset(addr) orelse return null;
        const off_usize: usize = @intCast(off);
        if (off_usize >= self.mem.len) return null;
        const available = self.mem[off_usize..@min(self.mem.len, off_usize + max_len)];
        const end = std.mem.indexOfScalar(u8, available, 0) orelse return null;
        return available[0..end];
    }

    fn cxxExceptionTypeName(self: *const MachOState, type_info_address: u64) ?[]const u8 {
        const name_address = self.read64(type_info_address +| 8);
        return self.guestCString(name_address, 4096);
    }

    fn cxxExceptionMessage(self: *const MachOState, object_address: u64) ?[]const u8 {
        const runtime_error_message = self.read64(object_address +| 8);
        if (self.guestCString(runtime_error_message, 4096)) |message| {
            if (message.len != 0) return message;
        }
        const message_view = compat_runtime.libcppStringView(self, object_address +| 8) orelse return null;
        if (message_view.length == 0 or message_view.length > 4096) return null;
        const message = self.guestMemoryConst(message_view.address, message_view.length) orelse return null;
        for (message) |byte| {
            if (byte < 0x20 or byte > 0x7E) return null;
        }
        return message;
    }

    fn guestWriteCString(self: *MachOState, addr: u64, bytes: []const u8) bool {
        if (self.guestMemory(addr, bytes.len + 1)) |buf| {
            @memcpy(buf[0..bytes.len], bytes);
            buf[bytes.len] = 0;
            return true;
        }
        return false;
    }

    fn standardStreamPointer(self: *MachOState, symbol_name: []const u8) ?u64 {
        const stream: struct { slot: *u64, handle: u64 } = if (std.mem.eql(u8, symbol_name, "___stdinp"))
            .{ .slot = &self.guest_stdin_pointer_address, .handle = GUEST_FILE_BASE }
        else if (std.mem.eql(u8, symbol_name, "___stdoutp"))
            .{ .slot = &self.guest_stdout_pointer_address, .handle = GUEST_FILE_BASE + 1 }
        else if (std.mem.eql(u8, symbol_name, "___stderrp"))
            .{ .slot = &self.guest_stderr_pointer_address, .handle = GUEST_FILE_BASE + 2 }
        else
            return null;
        if (stream.slot.* == 0) {
            stream.slot.* = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse return null;
            self.write64(stream.slot.*, stream.handle);
        }
        return stream.slot.*;
    }

    fn configureGuestLogMirror(self: *MachOState, args: []const []const u8) void {
        const prefix = "--log_file=";
        for (args) |arg| {
            if (!std.mem.startsWith(u8, arg, prefix) or arg.len == prefix.len) continue;
            const path = arg[prefix.len..];
            const path_z = self.allocator.dupeZ(u8, path) catch return;
            defer self.allocator.free(path_z);
            const flags = parseFopenFlags("a") orelse return;
            const fd = std.c.open(
                path_z.ptr,
                @bitCast(@as(u32, @intCast(flags))),
                @as(c_int, 0o666),
            );
            if (fd < 0) {
                std.debug.print("macho-processor: guest log mirror could not open {s}\n", .{path});
                return;
            }
            if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
            self.guest_log_mirror_fd = fd;
            std.debug.print("macho-processor: guest log mirror: {s}\n", .{path});
            return;
        }
    }

    fn hostWriteFdAll(fd: i32, bytes: []const u8) bool {
        if (fd < 0) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const result = std.c.write(fd, bytes.ptr + written, bytes.len - written);
            if (result <= 0) return false;
            written += @intCast(result);
        }
        return true;
    }

    fn emitGuestLog(self: *MachOState, prefix_char_raw: u64, address: u64, length_raw: u64) bool {
        const length = @min(length_raw, GUEST_LOG_BUFFER_SIZE);
        const message = self.guestMemoryConst(address, length) orelse return false;
        const raw_char: u8 = @truncate(prefix_char_raw);
        const prefix_char: u8 = if (raw_char >= 0x20 and raw_char <= 0x7E) raw_char else '?';
        var prefix_buffer: [32]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buffer, "[xenia] {c}> ", .{prefix_char}) catch return false;

        _ = hostWriteFdAll(1, prefix);
        _ = hostWriteFdAll(1, message);
        if (message.len == 0 or message[message.len - 1] != '\n') _ = hostWriteFdAll(1, "\n");

        if (self.guest_log_mirror_fd >= 0) {
            _ = hostWriteFdAll(self.guest_log_mirror_fd, prefix);
            _ = hostWriteFdAll(self.guest_log_mirror_fd, message);
            if (message.len == 0 or message[message.len - 1] != '\n') {
                _ = hostWriteFdAll(self.guest_log_mirror_fd, "\n");
            }
        }
        self.guest_log_line_count +|= 1;
        return true;
    }

    fn allocGuestFile(self: *MachOState, fd: i32, kind: GuestFileKind) ?u64 {
        for (&self.guest_files, 0..) |*file, idx| {
            if (!file.active) {
                file.* = .{
                    .active = true,
                    .fd = fd,
                    .position = 0,
                    .error_flag = false,
                    .kind = kind,
                };
                return GUEST_FILE_BASE + idx;
            }
        }
        return null;
    }

    fn guestFileFromHandle(self: *MachOState, handle: u64) ?*GuestFile {
        if (handle < GUEST_FILE_BASE) return null;
        const idx_u64 = handle - GUEST_FILE_BASE;
        if (idx_u64 >= GUEST_FILE_MAX) return null;
        const idx: usize = @intCast(idx_u64);
        const file = &self.guest_files[idx];
        if (!file.active) return null;
        return file;
    }

    fn closeGuestFiles(self: *MachOState) void {
        for (&self.guest_files) |*file| {
            if (!file.active) continue;
            if (file.kind == .regular and file.fd >= 0) {
                _ = std.c.close(file.fd);
            }
            file.* = .{};
        }
    }

    fn fileOffsetForVaddr(self: *const MachOState, vaddr: u64) ?u64 {
        for (self.segments) |seg| {
            if (vaddr < seg.vmaddr) continue;
            const delta = vaddr - seg.vmaddr;
            if (delta < seg.filesize) {
                return seg.fileoff + delta;
            }
        }
        return null;
    }

    fn logControlFlow(self: *const MachOState, kind: []const u8, from_rip: u64, to_rip: u64, decoded_len: u64, return_addr: ?u64) void {
        if (!self.verbose_trace) return;
        if (return_addr) |ret_addr| {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} ret=0x{x} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, ret_addr, self.regs.rsp });
        } else {
            log.info("cf({s}): rip=0x{x} -> 0x{x} len={d} rsp=0x{x}", .{ kind, from_rip, to_rip, decoded_len, self.regs.rsp });
        }
    }

    fn isStubPushJmpEntry(self: *const MachOState, rip: u64) ?struct { slot: u32, target: u64 } {
        const bytes = self.guestMemoryConst(rip, STUB_ENTRY_SIZE) orelse return null;
        if (bytes.len < STUB_ENTRY_SIZE) return null;
        if (bytes[0] != 0x68 or bytes[5] != 0xE9) return null;
        const slot = std.mem.readInt(u32, bytes[1..5], .little);
        const rel = std.mem.readInt(i32, bytes[6..10], .little);
        const target = @as(u64, @bitCast(@as(i64, @as(i64, @intCast(rip + STUB_ENTRY_SIZE)) + rel)));
        return .{ .slot = slot, .target = target };
    }

    fn isSharedStubHelper(self: *const MachOState, rip: u64) bool {
        const bytes = self.guestMemoryConst(rip, 16) orelse return false;
        if (bytes.len < 16) return false;
        return bytes[0] == 0x4C and bytes[1] == 0x8D and bytes[7] == 0x41 and bytes[8] == 0x53 and bytes[9] == 0xFF and bytes[10] == 0x25;
    }

    fn inHelperCluster(self: *const MachOState, rip: u64) bool {
        if (self.helper_cluster_start) |start| {
            const end = self.helper_cluster_end orelse start;
            return rip >= start and rip < end;
        }
        return false;
    }

    fn findSharedHelperCluster(self: *const MachOState, helper_rip: u64) ?struct { start: u64, end: u64 } {
        const helper_bytes = self.guestMemoryConst(helper_rip, 16) orelse return null;
        if (helper_bytes.len < 16) return null;
        var scan = helper_rip;
        var found_start: ?u64 = null;
        var count: usize = 0;
        while (count < 4096) : (count += 1) {
            if (scan < STUB_ENTRY_SIZE) break;
            scan -= STUB_ENTRY_SIZE;
            if (self.isStubPushJmpEntry(scan)) |stub| {
                if (stub.target == helper_rip) {
                    found_start = scan;
                    continue;
                }
            }
            break;
        }
        const start = found_start orelse return null;
        var end = start;
        count = 0;
        while (count < 4096) : (count += 1) {
            if (self.isStubPushJmpEntry(end)) |stub| {
                if (stub.target == helper_rip) {
                    end += STUB_ENTRY_SIZE;
                    continue;
                }
            }
            break;
        }
        return .{ .start = start, .end = end };
    }

    fn dumpGuestStack(self: *const MachOState) void {
        const count: usize = 12;
        std.debug.print("    [stack backtrace (rsp=0x{x}):\n", .{self.regs.rsp});
        var addr = self.regs.rsp;
        for (0..count) |i| {
            const val = self.read64(addr);
            if (val == 0) {
                std.debug.print("      [{d}] 0x{x}: 0x0\n", .{ i, addr });
            } else if (self.metadata.nearestSymbol(val)) |sym| {
                std.debug.print("      [{d}] 0x{x}: 0x{x} → {s}+0x{x}\n", .{ i, addr, val, sym.name, sym.offset });
            } else {
                std.debug.print("      [{d}] 0x{x}: 0x{x}\n", .{ i, addr, val });
            }
            addr +%= 8;
        }
    }

    fn handleStubHelperTransition(self: *MachOState) bool {
        if (self.isStubPushJmpEntry(self.regs.rip)) |stub| {
            self.pending_stub_slot = stub.slot;
            self.pending_stub_entry_rip = self.regs.rip;
            if (self.verbose_trace) log.info("stub-entry: rip=0x{x} slot=0x{x} shared_helper=0x{x}", .{ self.regs.rip, stub.slot, stub.target });
            self.regs.rip = stub.target;
            return true;
        }

        if (self.pending_stub_slot != null and self.isSharedStubHelper(self.regs.rip)) {
            const slot = self.pending_stub_slot.?;
            const entry_rip = self.pending_stub_entry_rip orelse self.regs.rip;
            const synthetic_return = self.read64(self.regs.rsp);
            if (self.findSharedHelperCluster(self.regs.rip)) |cluster| {
                self.helper_cluster_start = cluster.start;
                self.helper_cluster_end = cluster.end;
                if (self.verbose_trace) log.info("stub-helper cluster: helper_rip=0x{x} cluster=[0x{x}, 0x{x})", .{ self.regs.rip, cluster.start, cluster.end });
            }
            self.pending_stub_slot = null;
            self.pending_stub_entry_rip = null;
            if (self.pending_import_stub_rip) |import_stub_rip| {
                if (self.metadata.importAtStub(import_stub_rip)) |imported| {
                    switch (self.handleImport(imported)) {
                        .handled => |result| {
                            self.regs.rax = result;
                            if (self.verbose_trace) {
                                std.debug.print("  [handled import] {s} from {s}; stub=0x{x} return=0x{x} → rax=0x{x}\n", .{
                                    imported.name,
                                    imported.dylib,
                                    imported.stub_address,
                                    synthetic_return,
                                    result,
                                });
                            }
                        },
                        .handled_void => {
                            if (self.verbose_trace) {
                                std.debug.print(
                                    "  [handled void import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                                    .{ imported.name, imported.dylib, imported.stub_address, synthetic_return },
                                );
                            }
                        },
                        .control_transferred => {
                            self.pending_import_stub_rip = null;
                            if (self.verbose_trace) {
                                std.debug.print(
                                    "  [handled control transfer] {s} from {s}; landing_pad=0x{x}\n",
                                    .{ imported.name, imported.dylib, self.regs.rip },
                                );
                            }
                            return true;
                        },
                        .unsupported => |result| {
                            self.regs.rax = result;
                            self.recordUnresolvedImport(imported, synthetic_return, self.regs.rax);
                            if (self.metadata.nearestSymbol(synthetic_return)) |caller_sym| {
                                std.debug.print(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller={s}+0x{x} return=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, caller_sym.name, caller_sym.offset, synthetic_return, self.regs.rax },
                                );
                            } else {
                                std.debug.print(
                                    "  [unresolved import #{d}] {s} from {s}; stub=0x{x} caller=0x{x} → rax=0x{x}\n",
                                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, synthetic_return, self.regs.rax },
                                );
                            }
                            self.dumpGuestStack();
                            if (self.strict_imports) self.terminateForUnresolvedImport();
                        },
                        .terminated => |exit_code| {
                            self.exit_code = exit_code;
                            if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                            }
                            self.terminated = true;
                            std.debug.print("  [handled terminal import] {s}({d})\n", .{ imported.name, exit_code });
                        },
                    }
                }
            }
            self.pending_import_stub_rip = null;
            if (self.terminated) return true;
            if (synthetic_return != 0 and self.addrToOffset(synthetic_return) != null) {
                if (self.verbose_trace) log.warn("stub-helper aggressive fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x} synthetic_return=0x{x}; simulating resolved helper return", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                _ = self.pop();
                self.regs.rip = synthetic_return;
            } else {
                log.warn("stub-helper conservative fallback: helper_rip=0x{x} slot=0x{x} entry_rip=0x{x}; synthetic_return invalid (0x{x}), skipping helper entry", .{ self.regs.rip, slot, entry_rip, synthetic_return });
                self.regs.rip = entry_rip + STUB_ENTRY_SIZE;
            }
            return true;
        }

        if (self.inHelperCluster(self.regs.rip)) {
            const cluster_end = self.helper_cluster_end orelse self.regs.rip;
            log.warn("helper-cluster escape: rip=0x{x} cluster_end=0x{x}; forcing exit from packed stub region", .{ self.regs.rip, cluster_end });
            self.regs.rax = 0;
            self.regs.rip = cluster_end;
            self.helper_cluster_start = null;
            self.helper_cluster_end = null;
            return true;
        }

        return false;
    }

    fn handleImport(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        const name = imported.name;
        const return_address = self.read64(self.regs.rsp);
        const caller = if (self.metadata.nearestSymbol(return_address)) |symbol| symbol.name else "<unknown>";
        const active_initializer = self.initializer_resolver.current();
        const phase: import_resolution.Phase = if (active_initializer != null) .initializer else .execution;
        const owner = if (active_initializer) |initializer| initializer.symbol else "<main>";
        self.import_provider_override = null;
        self.import_confidence_override = null;
        const result = self.handleImportImpl(imported);

        const exact_contract = import_resolution.contractFor(name);
        const declared_contract = contract.resolveFromAllFamilies(name);
        const outcome: import_resolution.Outcome = switch (result) {
            .handled, .handled_void, .control_transferred => .resolved,
            .unsupported => .unresolved,
            .terminated => .terminated,
        };
        const inferred_provider: import_resolution.Provider = if (exact_contract != null)
            .contract
        else switch (result) {
            .unsupported => .none,
            else => if (declared_contract) |declared|
                switch (declared.strategy) {
                    .stub, .synthesize, .terminate => .contract,
                    else => .legacy_shim,
                }
            else
                .legacy_shim,
        };
        const inferred_confidence: import_resolution.Confidence = if (exact_contract != null)
            .verified
        else if (outcome == .unresolved)
            .unknown
        else
            .modeled;
        const provider = self.import_provider_override orelse inferred_provider;
        const confidence = self.import_confidence_override orelse inferred_confidence;
        self.import_resolver.record(name, caller, owner, phase, outcome, provider, confidence);
        return result;
    }

    fn handleImportImpl(self: *MachOState, imported: macho_metadata.ImportedSymbol) ImportHandlerResult {
        const name = imported.name;
        if (self.libcxx_streams.dispatch(self, &self.fs_forwarder, name)) |resolution| {
            self.import_provider_override = .libcpp_stream;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }
        if (import_resolution.dispatchContract(self, name)) |resolution| {
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
                .failed => .{ .unsupported = 0 },
            };
        }

        if (self.libcxx_filesystem.dispatch(self, &self.fs_forwarder, name)) |resolution| {
            self.import_provider_override = .libcpp_filesystem;
            self.import_confidence_override = .verified;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (self.pthreads.dispatch(self, name)) |resolution| {
            self.import_provider_override = .pthread_runtime;
            self.import_confidence_override = .modeled;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (self.dynamic_forwarder.forward(self, imported.dylib, name)) |resolution| {
            self.import_provider_override = .dynamic_library;
            self.import_confidence_override = .verified;
            return switch (resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (contract.dispatchFromAllFamilies(name, self.regs.rdi)) |outcome| {
            if (self.verbose_trace) {
                const c = contract.resolveFromAllFamilies(name);
                const tag = @tagName(outcome);
                std.debug.print("    [contract] {s} → {s}", .{ name, if (c) |cc| cc.name else "?" });
                switch (outcome) {
                    .handled => |val| std.debug.print(" ({s}) handled=0x{x}\n", .{ tag, val }),
                    .terminated => |code| std.debug.print(" ({s}) terminated={d}\n", .{ tag, code }),
                }
            }
            if (self.contract_verification) {
                if (contract.verify.verifyDispatch(name, outcome, self.regs.rdi)) {
                    return switch (outcome) {
                        .handled => |val| ImportHandlerResult{ .handled = val },
                        .terminated => |code| ImportHandlerResult{ .terminated = code },
                    };
                }
                if (contract.verify.resolveExpected(name, self.regs.rdi)) |expected| {
                    std.debug.print("    [contract] WARNING: {s} verification mismatch, using expected\n", .{name});
                    return switch (expected) {
                        .handled => |val| ImportHandlerResult{ .handled = val },
                        .terminated => |code| ImportHandlerResult{ .terminated = code },
                    };
                }
                std.debug.print("    [contract] WARNING: {s} verification mismatch, no expected fallback\n", .{name});
            }
            return switch (outcome) {
                .handled => |val| ImportHandlerResult{ .handled = val },
                .terminated => |code| ImportHandlerResult{ .terminated = code },
            };
        }

        if (std.mem.eql(u8, name, "_objc_getClass")) {
            const class_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
            const handle = self.compat.classNamed(class_name);
            std.debug.print("    [objc] class {s} -> 0x{x}\n", .{ class_name, handle });
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_sel_registerName")) {
            const selector_name = self.guestCString(self.regs.rdi, 1024) orelse return .{ .unsupported = 0 };
            const handle = self.compat.selectorNamed(selector_name);
            std.debug.print("    [objc] selector {s} -> 0x{x}\n", .{ selector_name, handle });
            return .{ .handled = handle };
        }
        if (std.mem.eql(u8, name, "_objc_msgSend")) {
            const result = self.compat.sendMessage(self.regs.rdi, self.regs.rsi);
            std.debug.print(
                "    [objc] msgSend receiver=0x{x} selector={s} -> 0x{x} modeled={}\n",
                .{ self.regs.rdi, result.selector_name, result.value, result.modeled },
            );
            return if (result.modeled) .{ .handled = result.value } else .{ .unsupported = result.value };
        }

        if (std.mem.eql(u8, name, "_objc_autoreleasePoolPush")) {
            return .{ .handled = self.compat.currentThreadHandle() };
        }
        if (std.mem.eql(u8, name, "___assert_rtn")) {
            self.guest_assertion_count += 1;
            const function_name = self.guestCString(self.regs.rdi, 1024) orelse "<unknown>";
            const file_name = self.guestCString(self.regs.rsi, 4096) orelse "<unknown>";
            const expression = self.guestCString(self.regs.rcx, 4096) orelse "<unknown>";
            std.debug.print(
                "macho-processor: guest assertion #{d}: {s}:{d} {s}: {s}\n",
                .{ self.guest_assertion_count, file_name, self.regs.rdx, function_name, expression },
            );
            if (self.initializer_resolver.current()) |initializer| {
                std.debug.print(
                    "  assertion owner: initializer [{d}/{d}] {s}\n",
                    .{ initializer.index + 1, self.metadata.initializer_addresses.len, initializer.symbol },
                );
                self.initializer_abort_requested = true;
            }
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "_strcmp")) {
            const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ordering = std.mem.order(u8, lhs, rhs);
            const result: i32 = switch (ordering) {
                .lt => -1,
                .eq => 0,
                .gt => 1,
            };
            return .{ .handled = @as(u32, @bitCast(result)) };
        }
        if (std.mem.eql(u8, name, "_strcasecmp")) {
            const lhs = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            const rhs = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const shared = @min(lhs.len, rhs.len);
            for (0..shared) |index| {
                const left = std.ascii.toLower(lhs[index]);
                const right = std.ascii.toLower(rhs[index]);
                if (left != right) {
                    const result: i32 = if (left < right) -1 else 1;
                    return .{ .handled = @as(u32, @bitCast(result)) };
                }
            }
            const result: i32 = if (lhs.len < rhs.len) -1 else if (lhs.len > rhs.len) 1 else 0;
            return .{ .handled = @as(u32, @bitCast(result)) };
        }
        if (std.mem.eql(u8, name, "_strcpy")) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const destination = self.guestMemory(self.regs.rdi, source.len + 1) orelse return .{ .unsupported = 0 };
            @memcpy(destination[0..source.len], source);
            destination[source.len] = 0;
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "_getenv")) {
            const key = self.guestCString(self.regs.rdi, 256) orelse return .{ .handled = 0 };
            const raw = if (std.mem.eql(u8, key, "HOME"))
                std.c.getenv("HOME")
            else if (std.mem.eql(u8, key, "XDG_DATA_HOME"))
                std.c.getenv("XDG_DATA_HOME")
            else if (std.mem.eql(u8, key, "TMPDIR"))
                std.c.getenv("TMPDIR")
            else if (std.mem.eql(u8, key, "USER"))
                std.c.getenv("USER")
            else if (std.mem.eql(u8, key, "PATH"))
                std.c.getenv("PATH")
            else
                null;
            const host_value = raw orelse return .{ .handled = 0 };
            const value = std.mem.sliceTo(host_value, 0);
            const allocation = self.guestAlloc(value.len + 1, 1) orelse return .{ .handled = 0 };
            if (!self.guestWriteCString(allocation, value)) return .{ .handled = 0 };
            return .{ .handled = allocation };
        }
        if (std.mem.eql(u8, name, "_getpwuid_r")) {
            if (self.regs.r8 != 0) self.write64(self.regs.r8, 0);
            return .{ .handled = 2 };
        }
        if (std.mem.eql(u8, name, "___error")) {
            if (self.guest_errno_address == 0) {
                self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return .{ .unsupported = 0 };
            }
            return .{ .handled = self.guest_errno_address };
        }

        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6__initEPKcm") != null) {
            const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
            if (self.verbose_trace) std.debug.print(
                "    [libc++] basic_string::__init(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, ok },
            );
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6assignEPKc") != null) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.initLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
            if (self.verbose_trace) std.debug.print(
                "    [libc++] basic_string::assign(this=0x{x}, source=0x{x}, length={d}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, source.len, ok },
            );
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSEc") != null) {
            const value = [_]u8{@truncate(self.regs.rsi)};
            const ok = compat_runtime.initLibcppStringLiteral(self, self.regs.rdi, &value);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKcm") != null) {
            const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6appendEPKc") != null) {
            const source = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.appendLibcppString(self, self.regs.rdi, self.regs.rsi, source.len);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE6insertEmPKc") != null) {
            const source = self.guestCString(self.regs.rdx, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.insertLibcppString(self, self.regs.rdi, self.regs.rsi, self.regs.rdx, source.len);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9__grow_byEmmmmmm") != null) {
            const inserted_size = self.read64(self.regs.rsp + 8);
            const ok = compat_runtime.growLibcppString(
                self,
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.rcx,
                self.regs.r8,
                self.regs.r9,
                inserted_size,
            );
            return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC1ERKS5_") != null or
            std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC2ERKS5_") != null)
        {
            const ok = compat_runtime.copyLibcppString(self, self.regs.rdi, self.regs.rsi);
            if (!ok) {
                std.debug.print(
                    "macho-processor: libc++ string copy rejected: destination=0x{x} source=0x{x} destination_mapped={} source_mapped={}\n",
                    .{ self.regs.rdi, self.regs.rsi, self.guestMemoryConst(self.regs.rdi, 24) != null, self.guestMemoryConst(self.regs.rsi, 24) != null },
                );
            }
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEaSERKS5_") != null) {
            const ok = compat_runtime.copyLibcppString(self, self.regs.rdi, self.regs.rsi);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "__ZNSt3__1plIcNS_11char_traitsIcEENS_9allocatorIcEEEENS_12basic_stringIT_T0_T1_EEPKS6_RKS9_") != null) {
            const left = self.guestCString(self.regs.rsi, 1 << 20) orelse return .{ .unsupported = 0 };
            const ok = compat_runtime.concatCStringAndLibcppString(self, self.regs.rdi, self.regs.rsi, left.len, self.regs.rdx);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED1Ev") != null or
            std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEED2Ev") != null)
        {
            const ok = compat_runtime.destroyLibcppString(self, self.regs.rdi);
            return if (ok) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.indexOf(u8, name, "basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE4findEcm") != null) {
            const string = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(string.address, string.length) orelse return .{ .unsupported = 0 };
            const start: usize = @intCast(@min(self.regs.rdx, string.length));
            const needle: u8 = @truncate(self.regs.rsi);
            const found = std.mem.indexOfScalarPos(u8, bytes, start, needle) orelse return .{ .handled = std.math.maxInt(u64) };
            return .{ .handled = found };
        }

        if (std.mem.eql(u8, name, "___cxa_guard_acquire")) {
            const result = compat_runtime.cxaGuardAcquire(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            return .{ .handled = result };
        }
        if (std.mem.eql(u8, name, "___cxa_guard_release")) {
            return if (compat_runtime.cxaGuardRelease(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "___cxa_guard_abort")) {
            return if (compat_runtime.cxaGuardAbort(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "___cxa_atexit")) {
            const registered = self.compat.registerAtexit(self.regs.rdi, self.regs.rsi, self.regs.rdx);
            if (self.verbose_trace) std.debug.print(
                "    [c++] __cxa_atexit(function=0x{x}, argument=0x{x}, dso=0x{x}) -> {}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, registered },
            );
            return .{ .handled = if (registered) 0 else 1 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__112__next_primeEm")) {
            return .{ .handled = nextPrime(self.regs.rdi) };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__18ios_base6xallocEv")) {
            const slot = self.ios_xalloc_next;
            self.ios_xalloc_next +%= 1;
            return .{ .handled = slot };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16chrono12system_clock3nowEv")) {
            const epoch_nanoseconds: u64 = 1_719_000_000 * 1_000_000_000;
            return .{ .handled = epoch_nanoseconds + self.monotonic_nanoseconds };
        }
        if (std.mem.indexOf(u8, name, "recursive_mutexC1Ev") != null or
            std.mem.indexOf(u8, name, "recursive_mutexC2Ev") != null)
        {
            if (self.guestMemory(self.regs.rdi, 64)) |storage| @memset(storage, 0);
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.indexOf(u8, name, "__thread_structC1Ev") != null or
            std.mem.indexOf(u8, name, "__thread_structC2Ev") != null)
        {
            if (self.guestMemory(self.regs.rdi, 64)) |storage| @memset(storage, 0);
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path16__root_directoryEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            self.regs.rdx = @intFromBool(bytes.len != 0 and bytes[0] == '/');
            return .{ .handled = path.address };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path10__filenameEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            const start = if (std.mem.lastIndexOfScalar(u8, bytes, '/')) |separator| separator + 1 else 0;
            self.regs.rdx = bytes.len - start;
            return .{ .handled = path.address + start };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__14__fs10filesystem4path13__parent_pathEv")) {
            const path = compat_runtime.libcppStringView(self, self.regs.rdi) orelse return .{ .unsupported = 0 };
            const bytes = self.guestMemoryConst(path.address, path.length) orelse return .{ .unsupported = 0 };
            var end = bytes.len;
            while (end > 1 and bytes[end - 1] == '/') end -= 1;
            const parent_length = if (std.mem.lastIndexOfScalar(u8, bytes[0..end], '/')) |separator|
                if (separator == 0) @as(usize, 1) else separator
            else
                0;
            self.regs.rdx = parent_length;
            return .{ .handled = path.address };
        }

        if (std.mem.eql(u8, name, "___dynamic_cast")) {
            if (self.dynamic_casts.resolve(
                self,
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.regs.rcx,
            )) |resolution| {
                return .{ .handled = resolution.address };
            }
            const return_address = self.read64(self.regs.rsp);
            if (self.metadata.nearestSymbol(return_address)) |caller| {
                if (std.mem.indexOf(u8, caller.name, "cxxopts") != null and
                    std.mem.indexOf(u8, caller.name, "OptionValue2as") != null)
                {
                    return .{ .handled = self.regs.rdi };
                }
            }
            std.debug.print(
                "macho-processor: __dynamic_cast metadata unresolved: source=0x{x} source_type=0x{x} destination_type=0x{x} hint={d}; returning null\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx, @as(i64, @bitCast(self.regs.rcx)) },
            );
            return .{ .handled = 0 };
        }

        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1Ev") or std.mem.eql(u8, name, "__ZNSt3__16localeC2Ev")) {
            const ok = self.compat.initLocale(self, self.regs.rdi, null);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeC1ERKS0_") or std.mem.eql(u8, name, "__ZNSt3__16localeC2ERKS0_")) {
            const ok = self.compat.initLocale(self, self.regs.rdi, self.regs.rsi);
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__16localeD1Ev") or std.mem.eql(u8, name, "__ZNSt3__16localeD2Ev")) {
            return if (self.compat.destroyLocale(self, self.regs.rdi)) .{ .handled = 0 } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__16locale9use_facetERNS0_2idE")) {
            const return_address = self.read64(self.regs.rsp);
            const caller_name = if (self.metadata.nearestSymbol(return_address)) |caller| caller.name else "";
            const kind: compat_runtime.LocaleFacetKind = if (std.mem.indexOf(u8, caller_name, "ctype") != null)
                .ctype
            else if (std.mem.indexOf(u8, caller_name, "collate") != null)
                .collate
            else
                .generic;
            const key = self.regs.rsi ^ (@as(u64, @intFromEnum(kind)) << 56);
            const facet = self.compat.localeFacet(self, key, kind) orelse return .{ .unsupported = 0 };
            return .{ .handled = facet };
        }
        if (std.mem.eql(u8, name, "__ZNKSt3__16locale4nameEv")) {
            const ok = compat_runtime.initLibcppStringLiteral(self, self.regs.rdi, "C");
            return if (ok) .{ .handled = self.regs.rdi } else .{ .unsupported = 0 };
        }
        if (std.mem.eql(u8, name, "__ZNSt3__115__get_classnameEPKcb")) {
            const class_name = self.guestCString(self.regs.rdi, 64) orelse return .{ .unsupported = 0 };
            const mask = compat_runtime.libcppRegexClassMask(class_name, self.regs.rsi != 0);
            return .{ .handled = mask };
        }
        if (std.mem.eql(u8, name, "___cxa_allocate_exception")) {
            const object_size = self.regs.rdi;
            const allocation = self.memory_forwarder.allocate(self, object_size +| 64, 16) orelse return .{ .unsupported = 0 };
            const object_address = allocation + 64;
            self.cxx_exceptions.recordAllocation(allocation, object_address, object_size, self.read64(self.regs.rsp));
            return .{ .handled = object_address };
        }
        if (std.mem.eql(u8, name, "___cxa_begin_catch")) {
            const object_address = self.cxx_exceptions.beginCatch(self.regs.rdi);
            std.debug.print("macho-processor: __cxa_begin_catch object=0x{x}\n", .{object_address});
            return .{ .handled = object_address };
        }
        if (std.mem.eql(u8, name, "___cxa_end_catch")) {
            const object_address = self.cxx_exceptions.endCatch();
            if (object_address) |object| std.debug.print("macho-processor: __cxa_end_catch object=0x{x}\n", .{object});
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "___cxa_get_exception_ptr")) {
            return .{ .handled = self.cxx_exceptions.exceptionPointer(self.regs.rdi) };
        }
        if (std.mem.eql(u8, name, "___cxa_free_exception")) {
            if (self.cxx_exceptions.freeException(self.regs.rdi)) |allocation| {
                self.memory_forwarder.release(allocation.storage_address);
            }
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "__ZNSt20bad_array_new_lengthC1Ev")) {
            return .{ .handled = self.regs.rdi };
        }
        if (std.mem.eql(u8, name, "___cxa_throw")) {
            const thrown = self.cxx_exceptions.recordThrow(
                self.regs.rdi,
                self.regs.rsi,
                self.regs.rdx,
                self.read64(self.regs.rsp),
            );
            std.debug.print(
                "macho-processor: guest raised C++ exception object=0x{x} type_info=0x{x} destructor=0x{x}\n",
                .{ self.regs.rdi, self.regs.rsi, self.regs.rdx },
            );
            if (self.cxxExceptionTypeName(thrown.type_info_address)) |type_name| {
                std.debug.print("macho-processor: C++ exception ABI type name: {s}\n", .{type_name});
            }
            if (self.metadata.nearestSymbol(thrown.type_info_address)) |symbol| {
                std.debug.print("macho-processor: C++ exception type: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.metadata.nearestSymbol(thrown.destructor_address)) |symbol| {
                std.debug.print("macho-processor: C++ exception destructor: {s}+0x{x}\n", .{ symbol.name, symbol.offset });
            }
            if (self.diagnosticSymbol(thrown.caller_address)) |throw_site| {
                std.debug.print("macho-processor: C++ exception throw site: {s}+0x{x} (0x{x})\n", .{
                    throw_site.symbol,
                    throw_site.symbol_offset,
                    throw_site.address,
                });
            }
            if (thrown.allocation) |allocation| {
                if (self.diagnosticSymbol(allocation.caller_address)) |allocation_site| {
                    std.debug.print("macho-processor: C++ exception allocation site: {s}+0x{x} (size={d})\n", .{
                        allocation_site.symbol,
                        allocation_site.symbol_offset,
                        allocation.object_size,
                    });
                }
            }
            if (self.cxxExceptionMessage(thrown.object_address)) |message| {
                std.debug.print("macho-processor: C++ exception message: {s}\n", .{message});
            }
            var inspection = self.unwinder.inspectThrow(self, thrown.type_info_address);
            const exception_header = if (thrown.allocation) |allocation|
                allocation.storage_address
            else
                thrown.object_address;
            if (self.unwinder.installPhaseTwo(self, &inspection, exception_header)) {
                self.last_unwind_inspection = inspection;
                return .control_transferred;
            }
            self.last_unwind_inspection = inspection;
            if (inspection.handler != null) {
                std.debug.print("macho-processor: stopping after verified phase-1 catch discovery because this frame layout is not phase-2 safe\n", .{});
            } else {
                std.debug.print("macho-processor: stopping after Itanium phase-1 found no matching catch handler\n", .{});
            }
            self.dumpGuestStack();
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "__Unwind_Resume")) {
            if (self.unwinder.resumePhaseTwo(self)) return .control_transferred;
            std.debug.print("macho-processor: guest requested exception resume without an active phase-2 cleanup chain\n", .{});
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }
        if (std.mem.eql(u8, name, "___cxa_rethrow")) {
            const object_address = self.cxx_exceptions.recordRethrow() orelse self.regs.rdi;
            const type_info = if (self.cxx_exceptions.last_throw) |thrown| thrown.type_info_address else 0;
            std.debug.print("macho-processor: guest rethrew exception object=0x{x}\n", .{object_address});
            self.last_unwind_inspection = self.unwinder.inspectThrow(self, type_info);
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.cxx_exception);
            return .{ .terminated = UNSUPPORTED_RUNTIME_EXIT_CODE };
        }

        if (std.mem.eql(u8, name, "__Znwm") or std.mem.eql(u8, name, "__Znam") or
            std.mem.endsWith(u8, name, "_malloc"))
        {
            return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rdi, 16) orelse 0 };
        }
        if (std.mem.eql(u8, name, "__ZdlPv") or std.mem.eql(u8, name, "__ZdaPv") or
            std.mem.eql(u8, name, "__ZdlPvm") or std.mem.eql(u8, name, "__ZdaPvm") or
            std.mem.endsWith(u8, name, "_free"))
        {
            self.memory_forwarder.release(self.regs.rdi);
            return .handled_void;
        }
        if (std.mem.endsWith(u8, name, "_realloc")) {
            return .{ .handled = self.memory_forwarder.reallocate(self, self.regs.rdi, self.regs.rsi) orelse 0 };
        }
        if (std.mem.eql(u8, name, "_posix_memalign")) {
            const output = self.regs.rdi;
            const alignment = self.regs.rsi;
            const size = self.regs.rdx;
            if (alignment < @sizeOf(u64) or !std.math.isPowerOfTwo(alignment)) {
                return .{ .handled = 22 };
            }
            if (self.guestMemory(output, @sizeOf(u64)) == null) return .{ .unsupported = 14 };
            const allocation = self.memory_forwarder.allocate(self, size, alignment) orelse return .{ .handled = 12 };
            self.write64(output, allocation);
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_aligned_alloc")) {
            const alignment = self.regs.rdi;
            if (!std.math.isPowerOfTwo(alignment) or self.regs.rsi % alignment != 0) return .{ .handled = 0 };
            return .{ .handled = self.memory_forwarder.allocate(self, self.regs.rsi, alignment) orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_calloc")) {
            return .{ .handled = self.memory_forwarder.allocateZeroed(self, self.regs.rdi, self.regs.rsi) orelse 0 };
        }
        if (std.mem.eql(u8, name, "____chkstk_darwin")) {
            return .{ .handled = self.regs.rax };
        }

        if (std.mem.endsWith(u8, name, "_memset")) {
            const dst = self.regs.rdi;
            const value: u8 = @intCast(self.regs.rsi & 0xFF);
            const count = self.regs.rdx;
            if (self.guestMemory(dst, count)) |buf| {
                @memset(buf, value);
                if (self.verbose_trace) std.debug.print("    [import] _memset(dst=0x{x}, value=0x{x}, count={d})\n", .{ dst, value, count });
            }
            return .{ .handled = dst };
        }

        if (std.mem.endsWith(u8, name, "_memcpy") or std.mem.endsWith(u8, name, "_memmove")) {
            const dst = self.regs.rdi;
            const src = self.regs.rsi;
            const count = self.regs.rdx;
            const src_buf = self.guestMemoryConst(src, count) orelse return .{ .unsupported = 0 };
            const dst_buf = self.guestMemory(dst, count) orelse return .{ .unsupported = 0 };
            std.mem.copyForwards(u8, dst_buf, src_buf);
            return .{ .handled = dst };
        }

        if (std.mem.endsWith(u8, name, "_memcmp")) {
            const lhs = self.guestMemoryConst(self.regs.rdi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const rhs = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return .{ .unsupported = 0 };
            const cmp = std.mem.order(u8, lhs, rhs);
            return .{ .handled = switch (cmp) {
                .lt => @bitCast(@as(i64, -1)),
                .eq => 0,
                .gt => 1,
            } };
        }

        if (std.mem.endsWith(u8, name, "_strlen")) {
            const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return .{ .unsupported = 0 };
            return .{ .handled = text.len };
        }

        if (std.mem.endsWith(u8, name, "_clock_getres")) {
            if (self.regs.rsi != 0) {
                if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
                self.write64(self.regs.rsi, 0);
                self.write64(self.regs.rsi + 8, 1);
            }
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_clock_gettime")) {
            if (self.guestMemory(self.regs.rsi, 16) == null) return .{ .unsupported = 14 };
            self.write64(self.regs.rsi, self.monotonic_nanoseconds / 1_000_000_000);
            self.write64(self.regs.rsi + 8, self.monotonic_nanoseconds % 1_000_000_000);
            self.monotonic_nanoseconds +%= 1_000_000;
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_gettimeofday")) {
            if (self.guestMemory(self.regs.rdi, 16) == null) return .{ .unsupported = 14 };
            const epoch_seconds: u64 = 1_719_000_000;
            self.write64(self.regs.rdi, epoch_seconds + self.monotonic_nanoseconds / 1_000_000_000);
            self.write64(self.regs.rdi + 8, (self.monotonic_nanoseconds % 1_000_000_000) / 1000);
            self.monotonic_nanoseconds +%= 1_000_000;
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_time")) {
            const now_i64: i64 = 1_719_000_000;
            const now: u64 = @bitCast(now_i64);
            const out_ptr = self.regs.rdi;
            if (out_ptr != 0) {
                if (self.guestMemory(out_ptr, 8)) |buf| {
                    std.mem.writeInt(u64, buf[0..8], now, .little);
                }
            }
            return .{ .handled = now };
        }

        if (std.mem.eql(u8, name, "_open")) {
            return .{ .handled = self.fs_forwarder.open(self) };
        }
        if (std.mem.eql(u8, name, "_write")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.write(self))) };
        }
        if (std.mem.eql(u8, name, "_close")) {
            return .{ .handled = self.fs_forwarder.close(self) };
        }
        if (std.mem.eql(u8, name, "_fstatat$INODE64") or std.mem.eql(u8, name, "_fstatat")) {
            return .{ .handled = self.fs_forwarder.fstatat(self) };
        }
        if (std.mem.eql(u8, name, "_openat")) {
            return .{ .handled = self.fs_forwarder.openat(self) };
        }
        if (std.mem.eql(u8, name, "_fstat$INODE64") or std.mem.eql(u8, name, "_fstat")) {
            return .{ .handled = self.fs_forwarder.fstat(self) };
        }
        if (std.mem.eql(u8, name, "_ftruncate")) {
            return .{ .handled = self.fs_forwarder.ftruncate(self) };
        }
        if (std.mem.eql(u8, name, "_opendir$INODE64") or std.mem.eql(u8, name, "_opendir")) {
            return .{ .handled = self.fs_forwarder.opendir(self) };
        }
        if (std.mem.eql(u8, name, "_dirfd")) {
            return .{ .handled = self.fs_forwarder.dirfd(self) };
        }
        if (std.mem.eql(u8, name, "_closedir")) {
            return .{ .handled = self.fs_forwarder.closedir(self) };
        }
        if (std.mem.eql(u8, name, "_readdir$INODE64") or std.mem.eql(u8, name, "_readdir")) {
            return .{ .handled = self.fs_forwarder.readdir(self) };
        }
        if (std.mem.eql(u8, name, "_read")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.read(self))) };
        }
        if (std.mem.eql(u8, name, "_readv")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readv(self))) };
        }
        if (std.mem.eql(u8, name, "_writev")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.writev(self))) };
        }
        if (std.mem.eql(u8, name, "_pread$INODE64") or std.mem.eql(u8, name, "_pread")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.pread(self))) };
        }
        if (std.mem.eql(u8, name, "_pwrite$INODE64") or std.mem.eql(u8, name, "_pwrite")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.pwrite(self))) };
        }
        if (std.mem.eql(u8, name, "_lseek$INODE64") or std.mem.eql(u8, name, "_lseek")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.lseek(self))) };
        }
        if (std.mem.eql(u8, name, "_stat$INODE64") or std.mem.eql(u8, name, "_stat")) {
            return .{ .handled = self.fs_forwarder.stat(self) };
        }
        if (std.mem.eql(u8, name, "_lstat$INODE64") or std.mem.eql(u8, name, "_lstat")) {
            return .{ .handled = self.fs_forwarder.lstat(self) };
        }
        if (std.mem.eql(u8, name, "_access") or std.mem.eql(u8, name, "_access$INODE64")) {
            return .{ .handled = self.fs_forwarder.access(self) };
        }
        if (std.mem.eql(u8, name, "_realpath$INODE64") or std.mem.eql(u8, name, "_realpath")) {
            return .{ .handled = self.fs_forwarder.realpath(self) };
        }
        if (std.mem.eql(u8, name, "_getcwd")) {
            return .{ .handled = self.fs_forwarder.getcwd(self) };
        }
        if (std.mem.eql(u8, name, "_chdir")) {
            return .{ .handled = self.fs_forwarder.chdir(self) };
        }
        if (std.mem.eql(u8, name, "_readlink$INODE64") or std.mem.eql(u8, name, "_readlink")) {
            return .{ .handled = @bitCast(@as(i64, self.fs_forwarder.readlink(self))) };
        }
        if (std.mem.eql(u8, name, "_dup")) {
            return .{ .handled = self.fs_forwarder.dup(self) };
        }
        if (std.mem.eql(u8, name, "_dup2")) {
            return .{ .handled = self.fs_forwarder.dup2(self) };
        }
        if (std.mem.eql(u8, name, "_fcntl")) {
            return .{ .handled = self.fs_forwarder.fcntl(self) };
        }
        if (std.mem.eql(u8, name, "_pipe")) {
            return .{ .handled = self.fs_forwarder.pipe(self) };
        }
        if (std.mem.eql(u8, name, "_mkdir") or std.mem.eql(u8, name, "_mkdir$INODE64")) {
            return .{ .handled = self.fs_forwarder.mkdir(self) };
        }
        if (std.mem.eql(u8, name, "_unlink") or std.mem.eql(u8, name, "_unlink$INODE64")) {
            return .{ .handled = self.fs_forwarder.unlink(self) };
        }
        if (std.mem.eql(u8, name, "_rename") or std.mem.eql(u8, name, "_rename$INODE64")) {
            return .{ .handled = self.fs_forwarder.rename(self) };
        }
        if (std.mem.eql(u8, name, "_symlink") or std.mem.eql(u8, name, "_symlink$INODE64")) {
            return .{ .handled = self.fs_forwarder.symlink(self) };
        }
        if (std.mem.eql(u8, name, "_mmap")) {
            return .{ .handled = self.fs_forwarder.mmap(self) };
        }
        if (std.mem.eql(u8, name, "_munmap")) {
            return .{ .handled = self.fs_forwarder.munmap(self) };
        }
        if (std.mem.eql(u8, name, "_mprotect")) {
            return .{ .handled = self.fs_forwarder.mprotect(self) };
        }
        if (std.mem.endsWith(u8, name, "_fopen")) {
            return .{ .handled = self.handleFopen() orelse 0 };
        }
        if (std.mem.endsWith(u8, name, "_fclose")) {
            return .{ .handled = self.handleFclose() };
        }
        if (std.mem.endsWith(u8, name, "_fprintf")) {
            return .{ .handled = self.handleFprintf() };
        }
        if (std.mem.endsWith(u8, name, "_fputs")) {
            return .{ .handled = self.handleFputs() };
        }
        if (std.mem.endsWith(u8, name, "_fwrite")) {
            return .{ .handled = self.handleFwrite() };
        }
        if (std.mem.endsWith(u8, name, "_fflush")) {
            return .{ .handled = self.handleFflush() };
        }
        if (std.mem.endsWith(u8, name, "_ftell")) {
            return .{ .handled = self.handleFtell() };
        }
        if (std.mem.endsWith(u8, name, "_fseek")) {
            return .{ .handled = self.handleFseek() };
        }
        if (std.mem.endsWith(u8, name, "_ferror")) {
            return .{ .handled = self.handleFerror() };
        }
        if (std.mem.endsWith(u8, name, "_printf")) {
            const arguments = [_]u64{ self.regs.rsi, self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
            return .{ .handled = self.handlePrintfLike(null, self.regs.rdi, &arguments) };
        }
        if (std.mem.endsWith(u8, name, "_putchar")) {
            return .{ .handled = self.handlePutchar() };
        }

        if (std.mem.eql(u8, name, "_sysctlbyname")) {
            const sysctl_name = self.guestCString(self.regs.rdi, 256) orelse return .{ .unsupported = 0 };
            if (std.mem.startsWith(u8, sysctl_name, "hw.optional.")) {
                if (self.regs.rsi != 0 and self.regs.rdx != 0) {
                    const old_len_ptr = self.guestMemory(self.regs.rdx, @sizeOf(u64)) orelse return .{ .unsupported = 0 };
                    const old_len = std.mem.readInt(u64, old_len_ptr[0..8], .little);
                    std.mem.writeInt(u64, old_len_ptr[0..8], @sizeOf(u32), .little);
                    if (old_len >= @sizeOf(u32) and self.regs.rsi != 0) {
                        const old_buf = self.guestMemory(self.regs.rsi, @sizeOf(u32)) orelse return .{ .unsupported = 0 };
                        std.mem.writeInt(u32, old_buf[0..4], 0, .little);
                    }
                }
                return .{ .handled = 0 };
            }
            return .{ .handled = @bitCast(@as(i64, -1)) };
        }
        if (std.mem.eql(u8, name, "_sigaction")) {
            return .{ .handled = 0 };
        }
        if (std.mem.eql(u8, name, "_setjmp")) {
            const env_bytes = self.guestMemory(self.regs.rdi, @sizeOf(u64) * 4) orelse return .{ .unsupported = 0 };
            std.mem.writeInt(u64, env_bytes[0..8], self.regs.rsp, .little);
            std.mem.writeInt(u64, env_bytes[8..16], self.regs.rbx, .little);
            std.mem.writeInt(u64, env_bytes[16..24], self.regs.rbp, .little);
            std.mem.writeInt(u64, env_bytes[24..32], self.regs.rip, .little);
            return .{ .handled = 0 };
        }

        if (std.mem.endsWith(u8, name, "_g_type_check_instance_cast")) {
            std.debug.print("    [import] _g_type_check_instance_cast compatibility shim → passthrough\n", .{});
            return .{ .handled = self.regs.rdi };
        }

        if (self.smart_stubs.resolve(name, imported.weak, self.regs.rdi)) |generated| {
            self.import_provider_override = .smart_stub;
            self.import_confidence_override = switch (generated.confidence) {
                .verified => .verified,
                .modeled => .modeled,
            };
            if (self.verbose_trace) {
                std.debug.print(
                    "    [smart stub] {s} reason={s} confidence={s}\n",
                    .{ name, @tagName(generated.reason), @tagName(generated.confidence) },
                );
            }
            return switch (generated.resolution) {
                .handled => |value| .{ .handled = value },
                .handled_void => .handled_void,
            };
        }

        if (self.verbose_trace) std.debug.print("    [import] (unhandled) {s}\n", .{name});
        return .{ .unsupported = 0 };
    }

    fn handleDirectImportCall(self: *MachOState, imported: macho_metadata.ImportedSymbol) void {
        const return_address = self.read64(self.regs.rsp);
        switch (self.handleImport(imported)) {
            .handled => |result| {
                self.regs.rax = result;
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled direct import] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address, result },
                    );
                }
            },
            .handled_void => {
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled void direct import] {s} from {s}; stub=0x{x} return=0x{x}\n",
                        .{ imported.name, imported.dylib, imported.stub_address, return_address },
                    );
                }
            },
            .control_transferred => {
                if (self.verbose_trace) {
                    std.debug.print(
                        "  [handled direct control transfer] {s} from {s}; landing_pad=0x{x}\n",
                        .{ imported.name, imported.dylib, self.regs.rip },
                    );
                }
                return;
            },
            .unsupported => |result| {
                self.regs.rax = result;
                self.recordUnresolvedImport(imported, return_address, result);
                std.debug.print(
                    "  [unresolved direct import #{d}] {s} from {s}; stub=0x{x} return=0x{x} -> rax=0x{x}\n",
                    .{ self.unresolved_import_count, imported.name, imported.dylib, imported.stub_address, return_address, result },
                );
                if (self.strict_imports) {
                    self.terminateForUnresolvedImport();
                    return;
                }
            },
            .terminated => |exit_code| {
                self.exit_code = exit_code;
                if (exit_diagnostics.reasonFromValue(self.termination_reason) == .unknown) {
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                }
                self.terminated = true;
                std.debug.print("  [handled terminal direct import] {s}({d})\n", .{ imported.name, exit_code });
                return;
            },
        }

        if (return_address != 0 and self.isExecutableAddress(return_address)) {
            _ = self.pop();
            self.regs.rip = return_address;
        } else {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
        }
    }

    fn recordUnresolvedImport(
        self: *MachOState,
        imported: macho_metadata.ImportedSymbol,
        return_address: u64,
        synthetic_result: u64,
    ) void {
        var entry = ImportTraceEntry{
            .symbol = imported.name,
            .dylib = imported.dylib,
            .stub_address = imported.stub_address,
            .return_address = return_address,
            .synthetic_result = synthetic_result,
        };
        if (self.metadata.nearestSymbol(return_address)) |caller_sym| {
            entry.caller_symbol = caller_sym.name;
            entry.caller_offset = caller_sym.offset;
        }
        self.import_trace_entries[self.import_trace_index] = entry;
        self.import_trace_index = (self.import_trace_index + 1) % IMPORT_TRACE_BUFFER_LEN;
        if (self.import_trace_index == 0) self.import_trace_filled = true;
        self.unresolved_import_count += 1;
    }

    fn terminateForUnresolvedImport(self: *MachOState) void {
        self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
        self.terminated = true;
    }

    fn terminateForInvalidControlTransfer(self: *MachOState, context: ControlTransferContext) void {
        var failure = exit_diagnostics.ControlTransferFailure{
            .kind = context.kind,
            .instruction_address = context.instruction_address,
            .operand_address = context.operand_address,
            .target_address = context.target_address,
            .return_address = context.return_address,
            .operand_mapped = context.operand_address != 0 and self.addrToOffset(context.operand_address) != null,
            .target_mapped = self.addrToOffset(context.target_address) != null,
            .target_executable = self.isExecutableAddress(context.target_address),
        };
        if (self.metadata.nearestSymbol(context.instruction_address)) |caller| {
            failure.caller_symbol = caller.name;
            failure.caller_offset = caller.offset;
        }
        if (self.metadata.nearestSymbol(context.target_address)) |target| {
            failure.target_symbol = target.name;
            failure.target_offset = target.offset;
        }
        for (self.metadata.imports) |imported| {
            if (imported.stub_address == context.instruction_address or
                (context.operand_address != 0 and imported.lazy_pointer_address == context.operand_address))
            {
                failure.candidate_import = imported.name;
                failure.candidate_image = imported.dylib;
                break;
            }
        }
        self.pending_control_transfer = null;
        self.terminal_control_transfer = failure;
        std.debug.print(
            "macho-processor: invalid control transfer: kind={s} instruction=0x{x} operand=0x{x} target=0x{x} return=0x{x} candidate_import={s}\n",
            .{
                failure.kind,
                failure.instruction_address,
                failure.operand_address,
                failure.target_address,
                failure.return_address,
                if (failure.candidate_import.len != 0) failure.candidate_import else "<none>",
            },
        );
        self.faulted = true;
        self.exit_code = 127;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
        self.terminated = true;
    }

    fn handleOpen(self: *MachOState) u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));

        const host_fd = std.c.open(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(self.regs.rsi))),
            @as(c_int, @intCast(self.regs.rdx & 0xFFFF)),
        );
        if (host_fd < 0) return @bitCast(@as(i64, -1));
        return self.registerGuestFd(host_fd) orelse @bitCast(@as(i64, -1));
    }

    fn registerGuestFd(self: *MachOState, host_fd: c_int) ?u64 {
        var guest_fd: usize = @intCast(@max(self.next_guest_fd, 3));
        while (guest_fd < self.guest_fds.len and self.guest_fds[guest_fd] >= 0) : (guest_fd += 1) {}
        if (guest_fd >= self.guest_fds.len) {
            _ = std.c.close(host_fd);
            return null;
        }
        self.guest_fds[guest_fd] = host_fd;
        self.next_guest_fd = guest_fd + 1;
        return guest_fd;
    }

    fn setGuestErrno(self: *MachOState, value: c_int) void {
        if (self.guest_errno_address == 0) {
            self.guest_errno_address = self.guestAlloc(@sizeOf(c_int), @alignOf(c_int)) orelse return;
        }
        const storage = self.guestMemory(self.guest_errno_address, @sizeOf(c_int)) orelse return;
        std.mem.writeInt(c_int, storage[0..@sizeOf(c_int)], value, .little);
    }

    fn hostFd(self: *MachOState, guest_or_host_fd: u64) ?c_int {
        if (guest_or_host_fd < self.guest_fds.len) {
            const guest_fd: usize = @intCast(guest_or_host_fd);
            if (self.guest_fds[guest_fd] >= 0) return self.guest_fds[guest_fd];
        }
        if (guest_or_host_fd > std.math.maxInt(c_int)) return null;
        return @intCast(guest_or_host_fd);
    }

    fn handleFstatat(self: *MachOState) u64 {
        const directory_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
        var host_stat: std.c.Stat = undefined;
        const result = std.c.fstatat(
            directory_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            &host_stat,
            @truncate(self.regs.rcx),
        );
        if (result != 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        const destination = self.guestMemory(self.regs.rdx, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
        @memcpy(destination, std.mem.asBytes(&host_stat));
        return 0;
    }

    fn handleOpenat(self: *MachOState) u64 {
        const directory_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const path = self.guestCString(self.regs.rsi, 4096) orelse return @bitCast(@as(i64, -1));
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return @bitCast(@as(i64, -1));
        path_buffer.append(self.allocator, 0) catch return @bitCast(@as(i64, -1));
        const host_fd = std.c.openat(
            directory_fd,
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            @bitCast(@as(u32, @truncate(self.regs.rdx))),
            @as(c_int, @intCast(self.regs.rcx & 0xFFFF)),
        );
        if (host_fd < 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        return self.registerGuestFd(host_fd) orelse @bitCast(@as(i64, -1));
    }

    fn handleFstat(self: *MachOState) u64 {
        const host_fd = self.hostFd(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        var host_stat: std.c.Stat = undefined;
        if (std.c.fstat(host_fd, &host_stat) != 0) {
            self.setGuestErrno(2);
            return @bitCast(@as(i64, -1));
        }
        const destination = self.guestMemory(self.regs.rsi, @sizeOf(std.c.Stat)) orelse return @bitCast(@as(i64, -1));
        @memcpy(destination, std.mem.asBytes(&host_stat));
        return 0;
    }

    fn handleFtruncate(self: *MachOState) u64 {
        const host_fd = self.hostFd(self.regs.rdi) orelse {
            self.setGuestErrno(9);
            return @bitCast(@as(i64, -1));
        };
        const result = std.c.ftruncate(host_fd, @bitCast(self.regs.rsi));
        if (result != 0) self.setGuestErrno(22);
        return @bitCast(@as(i64, result));
    }

    fn handleOpendir(self: *MachOState) ?u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
        var path_buffer = std.ArrayList(u8).empty;
        defer path_buffer.deinit(self.allocator);
        path_buffer.appendSlice(self.allocator, path) catch return null;
        path_buffer.append(self.allocator, 0) catch return null;
        const host_fd = std.c.open(
            @as([*:0]const u8, @ptrCast(path_buffer.items.ptr)),
            std.c.O{ .DIRECTORY = true },
            @as(c_int, 0),
        );
        if (host_fd < 0) return null;
        return self.allocGuestFile(host_fd, .regular) orelse {
            _ = std.c.close(host_fd);
            return null;
        };
    }

    fn handleClosedir(self: *MachOState) u64 {
        const directory = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (directory.fd >= 0 and std.c.close(directory.fd) != 0) return @bitCast(@as(i64, -1));
        directory.* = .{};
        return 0;
    }

    fn handleWrite(self: *MachOState) u64 {
        const guest_fd: usize = @intCast(self.regs.rdi);
        if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
        const bytes = self.guestMemoryConst(self.regs.rsi, self.regs.rdx) orelse return @bitCast(@as(i64, -1));
        const written = std.c.write(self.guest_fds[guest_fd], bytes.ptr, bytes.len);
        return if (written < 0) @bitCast(@as(i64, -1)) else @intCast(written);
    }

    fn handleClose(self: *MachOState) u64 {
        const guest_fd: usize = @intCast(self.regs.rdi);
        if (guest_fd >= self.guest_fds.len or self.guest_fds[guest_fd] < 0) return @bitCast(@as(i64, -1));
        const result = std.c.close(self.guest_fds[guest_fd]);
        self.guest_fds[guest_fd] = -1;
        if (guest_fd < self.next_guest_fd) self.next_guest_fd = @max(guest_fd, 3);
        return if (result == 0) 0 else @bitCast(@as(i64, -1));
    }

    fn hostWriteAll(self: *MachOState, file: *GuestFile, bytes: []const u8) bool {
        _ = self;
        if (file.fd < 0) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const rc = std.c.write(file.fd, bytes.ptr + written, bytes.len - written);
            if (rc < 0) {
                file.error_flag = true;
                return false;
            }
            if (rc == 0) break;
            written += @intCast(rc);
        }
        if (file.kind == .regular) file.position += @intCast(written);
        return written == bytes.len;
    }

    fn handleFopen(self: *MachOState) ?u64 {
        const path = self.guestCString(self.regs.rdi, 4096) orelse return null;
        const mode = self.guestCString(self.regs.rsi, 32) orelse return null;
        const flags = parseFopenFlags(mode) orelse return null;
        var path_buf = std.ArrayList(u8).empty;
        defer path_buf.deinit(self.allocator);
        path_buf.appendSlice(self.allocator, path) catch return null;
        path_buf.append(self.allocator, 0) catch return null;
        const zpath: [*:0]const u8 = @ptrCast(path_buf.items.ptr);
        const fd = std.c.open(zpath, @bitCast(@as(u32, @intCast(flags))), @as(c_int, 0o666));
        if (fd < 0) return null;
        return self.allocGuestFile(fd, .regular);
    }

    fn handleFclose(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (file.kind == .regular and file.fd >= 0) {
            if (std.c.close(file.fd) != 0) {
                file.error_flag = true;
                return @bitCast(@as(i64, -1));
            }
        }
        file.* = .{};
        return 0;
    }

    fn handleFputs(self: *MachOState) u64 {
        const text = self.guestCString(self.regs.rdi, 1 << 20) orelse return @bitCast(@as(i64, -1));
        const file = self.guestFileFromHandle(self.regs.rsi) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(file, text)) return @bitCast(@as(i64, -1));
        return @intCast(text.len);
    }

    fn handleFwrite(self: *MachOState) u64 {
        const element_size = self.regs.rsi;
        const element_count = self.regs.rdx;
        if (element_size == 0 or element_count == 0) return 0;
        const byte_count = std.math.mul(u64, element_size, element_count) catch return 0;
        const bytes = self.guestMemoryConst(self.regs.rdi, byte_count) orelse return 0;
        const file = self.guestFileFromHandle(self.regs.rcx) orelse return 0;
        if (!self.hostWriteAll(file, bytes)) return 0;
        return element_count;
    }

    fn handleFflush(self: *MachOState) u64 {
        if (self.regs.rdi == 0) return 0;
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        if (std.c.fsync(file.fd) != 0 and file.kind == .regular) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
        return 0;
    }

    fn handleFtell(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        return @bitCast(file.position);
    }

    fn handleFseek(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const offset: i64 = @bitCast(self.regs.rsi);
        const whence: i32 = @intCast(self.regs.rdx);
        if (file.fd < 0) return @bitCast(@as(i64, -1));
        const pos = std.c.lseek(file.fd, offset, whence);
        if (pos < 0) {
            file.error_flag = true;
            return @bitCast(@as(i64, -1));
        }
        file.position = pos;
        return 0;
    }

    fn handleFerror(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return 1;
        return if (file.error_flag) 1 else 0;
    }

    fn handleFprintf(self: *MachOState) u64 {
        const file = self.guestFileFromHandle(self.regs.rdi) orelse return @bitCast(@as(i64, -1));
        const arguments = [_]u64{ self.regs.rdx, self.regs.rcx, self.regs.r8, self.regs.r9 };
        return self.handlePrintfLike(file, self.regs.rsi, &arguments);
    }

    fn handlePrintfLike(self: *MachOState, file_opt: ?*GuestFile, format_address: u64, arguments: []const u64) u64 {
        const format = self.guestCString(format_address, 1 << 20) orelse return @bitCast(@as(i64, -1));
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var output = std.ArrayList(u8).empty;
        defer output.deinit(allocator);

        var gp_index: usize = 0;
        var stack_arg_addr = self.regs.rsp + 8;
        var i: usize = 0;
        while (i < format.len) : (i += 1) {
            if (format[i] != '%') {
                output.append(allocator, format[i]) catch return @bitCast(@as(i64, -1));
                continue;
            }
            i += 1;
            if (i >= format.len) break;
            if (format[i] == '%') {
                output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                continue;
            }

            while (i < format.len and (format[i] == '-' or format[i] == '+' or format[i] == ' ' or format[i] == '#' or format[i] == '0')) : (i += 1) {}
            while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            if (i < format.len and format[i] == '.') {
                i += 1;
                while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
            }
            while (i < format.len and
                (format[i] == 'l' or format[i] == 'h' or format[i] == 'z' or
                    format[i] == 't' or format[i] == 'j' or format[i] == 'L')) : (i += 1)
            {}
            if (i >= format.len) break;

            const spec = format[i];
            const arg = self.nextVarArg(arguments, &gp_index, &stack_arg_addr);
            switch (spec) {
                's' => {
                    const text = self.guestCString(arg, 1 << 20) orelse "(null)";
                    output.appendSlice(allocator, text) catch return @bitCast(@as(i64, -1));
                },
                'd', 'i' => {
                    const val: i64 = @bitCast(arg);
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{val}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'u' => {
                    const rendered = std.fmt.allocPrint(allocator, "{}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'x' => {
                    const rendered = std.fmt.allocPrint(allocator, "{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'X' => {
                    const rendered = std.fmt.allocPrint(allocator, "{X}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'p' => {
                    const rendered = std.fmt.allocPrint(allocator, "0x{x}", .{arg}) catch return @bitCast(@as(i64, -1));
                    output.appendSlice(allocator, rendered) catch return @bitCast(@as(i64, -1));
                },
                'c' => {
                    output.append(allocator, @intCast(arg & 0xFF)) catch return @bitCast(@as(i64, -1));
                },
                else => {
                    output.append(allocator, '%') catch return @bitCast(@as(i64, -1));
                    output.append(allocator, spec) catch return @bitCast(@as(i64, -1));
                },
            }
        }

        const sink = file_opt orelse self.guestFileFromHandle(GUEST_FILE_BASE + 1).?;
        if (!self.hostWriteAll(sink, output.items)) return @bitCast(@as(i64, -1));
        return output.items.len;
    }

    fn handlePutchar(self: *MachOState) u64 {
        const ch: u8 = @intCast(self.regs.rdi & 0xFF);
        const sink = self.guestFileFromHandle(GUEST_FILE_BASE + 1) orelse return @bitCast(@as(i64, -1));
        if (!self.hostWriteAll(sink, &[_]u8{ch})) return @bitCast(@as(i64, -1));
        return ch;
    }

    fn handleGtkInitCheck(self: *MachOState) u64 {
        const argc_ptr = self.regs.rdi;
        const argv_ptr = self.regs.rsi;
        _ = argc_ptr;
        _ = argv_ptr;
        std.debug.print("    [import] _gtk_init_check compatibility shim → success\n", .{});
        return 1;
    }

    fn nextVarArg(self: *const MachOState, arguments: []const u64, gp_index: *usize, stack_arg_addr: *u64) u64 {
        if (gp_index.* < arguments.len) {
            defer gp_index.* += 1;
            return arguments[gp_index.*];
        }
        const addr = stack_arg_addr.*;
        stack_arg_addr.* += 8;
        return self.read64(addr);
    }

    fn recordTrace(self: *MachOState, decoded: DecodedInsn) void {
        self.trace_entries[self.trace_index] = .{
            .rip = self.regs.rip,
            .op = decoded.op,
            .len = decoded.len,
            .rsp = self.regs.rsp,
            .rax = self.regs.rax,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
        };
        self.trace_index = (self.trace_index + 1) % TRACE_BUFFER_LEN;
        if (self.trace_index == 0) self.trace_filled = true;
    }

    fn shouldTraceRIP(self: *const MachOState, rip: u64) bool {
        if (self.trace_range_start) |start| {
            const end = self.trace_range_end orelse start;
            return rip >= start and rip <= end;
        }
        return false;
    }

    fn dumpRecentTrace(self: *const MachOState) void {
        const count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (count == 0) return;
        log.err("recent trace dump (most recent last, count={d})", .{count});
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const idx = if (self.trace_filled)
                (self.trace_index + i) % TRACE_BUFFER_LEN
            else
                i;
            const entry = self.trace_entries[idx];
            log.err("trace[{d}]: rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                i,
                entry.rip,
                @tagName(entry.op),
                entry.len,
                entry.rsp,
                entry.rax,
                entry.rcx,
                entry.rdx,
            });
        }
    }

    fn regVal(self: *const MachOState, id: RegId, size: Size) u64 {
        return x64_decoder.regVal(&self.regs, id, size);
    }

    fn setReg(self: *MachOState, id: RegId, size: Size, val: u64) void {
        x64_decoder.setReg(&self.regs, id, size, val);
    }

    fn setFlagsSub(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applySub(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsAdd(self: *MachOState, a: u64, b: u64, result: u64, size: Size) void {
        x64_decoder.applyAdd(&self.regs.rflags, a, b, result, size);
    }

    fn setFlagsIncDec(self: *MachOState, input: u64, result: u64, size: Size, is_inc: bool) void {
        x64_decoder.applyIncDec(&self.regs.rflags, input, result, size, is_inc);
    }

    fn setFlagsLogic(self: *MachOState, result: u64, size: Size) void {
        x64_decoder.applyLogic(&self.regs.rflags, result, size);
    }

    fn setFlag(self: *MachOState, flag: u32, enabled: bool) void {
        if (enabled) {
            self.regs.rflags |= flag;
        } else {
            self.regs.rflags &= ~flag;
        }
    }

    fn bitWidth(size: Size) u7 {
        return switch (size) {
            .bits8 => 8,
            .bits16 => 16,
            .bits32 => 32,
            .bits64 => 64,
        };
    }

    fn maskForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0xFF,
            .bits16 => 0xFFFF,
            .bits32 => 0xFFFF_FFFF,
            .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
        };
    }

    fn signBitForSize(size: Size) u64 {
        return switch (size) {
            .bits8 => 0x80,
            .bits16 => 0x8000,
            .bits32 => 0x8000_0000,
            .bits64 => 0x8000_0000_0000_0000,
        };
    }

    fn arithmeticShiftRight(value: u64, size: Size, count: u6) u64 {
        const signed: i64 = switch (size) {
            .bits8 => @as(i8, @bitCast(@as(u8, @truncate(value)))),
            .bits16 => @as(i16, @bitCast(@as(u16, @truncate(value)))),
            .bits32 => @as(i32, @bitCast(@as(u32, @truncate(value)))),
            .bits64 => @bitCast(value),
        };
        return @as(u64, @bitCast(signed >> count)) & maskForSize(size);
    }

    fn setupInitialStack(self: *MachOState, args: []const []const u8) void {
        var sp = self.mem_base + self.mem_size;

        sp -= 8;
        self.write64(sp, 0);

        sp -= 8;
        const envp_addr = sp;
        self.write64(sp, 0);

        var arg_addrs: std.ArrayList(u64) = .empty;
        defer arg_addrs.deinit(self.allocator);
        for (args) |arg| {
            sp -|= arg.len + 1;
            for (arg, 0..) |c, i| {
                self.write8(sp + i, c);
            }
            self.write8(sp + arg.len, 0);
            arg_addrs.append(self.allocator, sp) catch {};
        }

        sp -= 8;
        self.write64(sp, 0);

        for (0..arg_addrs.items.len) |i| {
            sp -= 8;
            self.write64(sp, arg_addrs.items[arg_addrs.items.len - 1 - i]);
        }
        const argv_addr = sp;

        sp -= 8;
        const argc_val: u64 = @intCast(args.len);
        self.write64(sp, argc_val);

        sp &= ~@as(u64, 15);
        sp -= 8;

        self.regs.rdi = argc_val;
        self.regs.rsi = argv_addr;
        self.regs.rdx = envp_addr;
        self.regs.rsp = sp;
    }

    fn setupMachOState(self: *MachOState, path: []const u8, args: []const []const u8) void {
        self.configureGuestLogMirror(args);
        self.launch_options.configure(args);
        var argument_index: usize = 0;
        while (argument_index < args.len) : (argument_index += 1) {
            const argument = args[argument_index];
            if (std.mem.eql(u8, argument, "--storage_root") and argument_index + 1 < args.len) {
                self.fs_forwarder.configurePaths(args[argument_index + 1]);
                break;
            }
            const prefix = "--storage_root=";
            if (std.mem.startsWith(u8, argument, prefix)) {
                self.fs_forwarder.configurePaths(argument[prefix.len..]);
                break;
            }
        }
        var full_args = std.ArrayList([]const u8).empty;
        defer full_args.deinit(self.allocator);
        full_args.append(self.allocator, path) catch {};
        for (args) |a| full_args.append(self.allocator, a) catch {};

        self.trace_range_start = 0x1332000;
        self.trace_range_end = 0x1333000;
        self.setupInitialStack(full_args.items);
        self.regs.rip = self.entry_point_vaddr;
    }

    fn initializerAbi(self: *const MachOState) initialization_resolution.AbiSnapshot {
        return .{
            .rsp = self.regs.rsp,
            .rbx = self.regs.rbx,
            .rbp = self.regs.rbp,
            .r12 = self.regs.r12,
            .r13 = self.regs.r13,
            .r14 = self.regs.r14,
            .r15 = self.regs.r15,
        };
    }

    fn beginInitializerTransaction(self: *MachOState) void {
        self.initializer_memory.begin();
        self.initializer_checkpoint = .{
            .heap_next = self.heap_next,
            .compat = self.compat,
            .monotonic_nanoseconds = self.monotonic_nanoseconds,
            .ios_xalloc_next = self.ios_xalloc_next,
            .cxxopts_split_accelerations = self.cxxopts_split_accelerations,
            .guest_errno_address = self.guest_errno_address,
        };
    }

    fn rollbackInitializerTransaction(self: *MachOState) bool {
        const checkpoint = self.initializer_checkpoint orelse return false;
        const complete = self.initializer_memory.rollback(self.mem);
        self.heap_next = checkpoint.heap_next;
        self.compat = checkpoint.compat;
        self.monotonic_nanoseconds = checkpoint.monotonic_nanoseconds;
        self.ios_xalloc_next = checkpoint.ios_xalloc_next;
        self.cxxopts_split_accelerations = checkpoint.cxxopts_split_accelerations;
        self.guest_errno_address = checkpoint.guest_errno_address;
        self.initializer_checkpoint = null;
        return complete;
    }

    fn commitInitializerTransaction(self: *MachOState) bool {
        if (self.initializer_checkpoint == null) return false;
        self.initializer_checkpoint = null;
        return self.initializer_memory.commit();
    }

    fn runOneInitializer(self: *MachOState, launch_regs: Regs, index: usize, is_retry: bool) InitializerRunOutcome {
        const address = self.metadata.initializer_addresses[index];
        const nearest_symbol = self.metadata.nearestSymbol(address);
        const symbol_name = if (nearest_symbol) |symbol| symbol.name else "<unknown>";
        self.regs = launch_regs;
        self.initializer_abort_requested = false;

        if (is_retry) {
            if (!self.initializer_resolver.retry(
                index,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            )) return .failed;
        } else {
            if (!self.initializer_resolver.begin(
                index,
                address,
                symbol_name,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            )) {
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                self.terminated = true;
                return .failed;
            }
        }

        self.beginInitializerTransaction();

        if (!self.isExecutableAddress(address)) {
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] has invalid target 0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, address },
            );
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.fail(
                .invalid_target,
                0,
                self.initializerAbi(),
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            return .failed;
        }

        self.push(INITIALIZER_RETURN_SENTINEL);
        self.regs.rip = address;

        var steps: u64 = 0;
        while (!self.terminated and !self.initializer_abort_requested and
            self.regs.rip != INITIALIZER_RETURN_SENTINEL and steps < INITIALIZER_STEP_LIMIT) : (steps += 1)
        {
            if (!self.step()) break;
        }
        if (self.initializer_abort_requested) {
            const final_abi = self.initializerAbi();
            if (!self.rollbackInitializerTransaction()) {
                self.initializer_resolver.fail(
                    .transaction_failed,
                    steps,
                    final_abi,
                    self.unresolved_import_count,
                    self.guest_assertion_count,
                );
                self.faulted = true;
                self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
                self.terminated = true;
                return .failed;
            }
            self.initializer_resolver.deferCurrent(
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            self.initializer_abort_requested = false;
            std.debug.print(
                "macho-processor: deferred initializer [{d}/{d}] {s} after assertion\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name },
            );
            return .deferred;
        }
        if (self.terminated) {
            const final_abi = self.initializerAbi();
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] terminated at rip=0x{x} reason={s} exit_code=0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, self.regs.rip, @tagName(exit_diagnostics.reasonFromValue(self.termination_reason)), self.exit_code },
            );
            self.dumpRecentTrace();
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.fail(
                .terminated,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] failed at {s}+0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name, if (nearest_symbol) |item| item.offset else address },
            );
            return .failed;
        }
        if (self.regs.rip != INITIALIZER_RETURN_SENTINEL) {
            const final_abi = self.initializerAbi();
            std.debug.print(
                "macho-processor: initializer [{d}/{d}] exceeded {d} steps at {s}+0x{x}; terminal_rip=0x{x}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, INITIALIZER_STEP_LIMIT, symbol_name, if (nearest_symbol) |item| item.offset else address, self.regs.rip },
            );
            self.dumpRecentTrace();
            _ = self.rollbackInitializerTransaction();
            self.initializer_resolver.fail(
                .step_limit,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.max_steps_reached);
            self.terminated = true;
            return .failed;
        }

        const final_abi = self.initializerAbi();
        if (!self.commitInitializerTransaction()) {
            self.initializer_resolver.fail(
                .transaction_failed,
                steps,
                final_abi,
                self.unresolved_import_count,
                self.guest_assertion_count,
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.terminated = true;
            return .failed;
        }

        const degraded_before = self.initializer_resolver.degraded;
        self.initializer_resolver.finish(
            steps,
            final_abi,
            self.unresolved_import_count,
            self.guest_assertion_count,
        );
        if (self.strict_initializers and self.initializer_resolver.degraded != degraded_before) {
            std.debug.print(
                "macho-processor: strict initializer mode rejected [{d}/{d}] {s}\n",
                .{ index + 1, self.metadata.initializer_addresses.len, symbol_name },
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
            return .failed;
        }
        return .completed;
    }

    fn runInitializers(self: *MachOState) bool {
        if (self.metadata.initializer_addresses.len == 0) return true;

        const launch_regs = self.regs;
        var pending: std.ArrayList(usize) = .empty;
        defer pending.deinit(self.allocator);
        var next_pending: std.ArrayList(usize) = .empty;
        defer next_pending.deinit(self.allocator);

        for (self.metadata.initializer_addresses, 0..) |_, index| {
            switch (self.runOneInitializer(launch_regs, index, false)) {
                .completed => {},
                .deferred => pending.append(self.allocator, index) catch return false,
                .failed => return false,
            }
            if ((index + 1) % 50 == 0 or index + 1 == self.metadata.initializer_addresses.len) {
                std.debug.print(
                    "macho-processor: processed initializer {d}/{d}\n",
                    .{ index + 1, self.metadata.initializer_addresses.len },
                );
            }
        }

        var retry_round: u8 = 0;
        while (pending.items.len != 0 and retry_round < 3) : (retry_round += 1) {
            std.debug.print(
                "macho-processor: retrying {d} deferred initializer(s), pass {d}\n",
                .{ pending.items.len, retry_round + 1 },
            );
            for (pending.items) |index| {
                switch (self.runOneInitializer(launch_regs, index, true)) {
                    .completed => {},
                    .deferred => next_pending.append(self.allocator, index) catch return false,
                    .failed => return false,
                }
            }
            pending.clearRetainingCapacity();
            std.mem.swap(std.ArrayList(usize), &pending, &next_pending);
        }

        if (pending.items.len != 0) {
            std.debug.print(
                "macho-processor: {d} initializer(s) remained deferred after 3 retry passes\n",
                .{pending.items.len},
            );
            self.faulted = true;
            self.exit_code = UNSUPPORTED_RUNTIME_EXIT_CODE;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            self.terminated = true;
            return false;
        }

        self.regs = launch_regs;
        return true;
    }

    fn handleInternalCompatibility(self: *MachOState) bool {
        if (self.internal_targets.parse_launch_arguments != 0 and
            self.regs.rip == self.internal_targets.parse_launch_arguments)
        {
            self.startup.enter(.launch_arguments, self.executed_steps);
            self.capturePositionalLaunchOptions();
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
        if (self.handleGuestLogBridge()) return true;
        for (self.internal_targets.cvar_add_to_launch_options[0..self.internal_targets.cvar_add_to_launch_options_count]) |target| {
            if (self.regs.rip != target) continue;
            const view = compat_runtime.libcppStringView(self, self.regs.rdi + 8) orelse return false;
            const name = self.guestMemoryConst(view.address, view.length) orelse return false;
            if (self.launch_options.shouldRegister(name)) return false;
            if (self.launch_options.registrations_skipped == 1 or
                self.launch_options.registrations_skipped % 100 == 0)
            {
                std.debug.print(
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
            return self.handleCxxoptsSplitOptionNames();
        }
        if (self.internal_targets.libcxx_basic_streambuf_pubsetbuf != 0 and
            self.regs.rip == self.internal_targets.libcxx_basic_streambuf_pubsetbuf)
        {
            self.regs.rax = self.libcxx_streams.handlePubsetbuf(self.regs.rdi, self.regs.rsi, self.regs.rdx);
            self.regs.rip = self.pop();
            return true;
        }
        if (self.internal_targets.print_config_to_log != 0 and
            self.regs.rip == self.internal_targets.print_config_to_log)
        {
            self.startup.enter(.configuration, self.executed_steps);
            if (self.diagnostic_text.buildConfigDump(self, &self.fs_forwarder, self.regs.rdi)) |dump| {
                const emitted = self.emitGuestLog('i', dump.address, dump.length);
                self.logging.recordEmission(dump.length, emitted);
                self.regs.rip = self.pop();
                return true;
            }
        }
        return false;
    }

    fn capturePositionalLaunchOptions(self: *MachOState) void {
        if (self.positional_options_captured) return;
        self.positional_options_captured = true;

        const vector = self.regs.r8;
        const begin = self.read64(vector);
        const end = self.read64(vector + 8);
        if (begin == 0 or end < begin or (end - begin) % 24 != 0) {
            std.debug.print("macho-processor: launch option acceleration could not decode positional option vector at 0x{x}\n", .{vector});
            return;
        }
        const count = @min((end - begin) / 24, launch_argument_accelerator.MAX_REQUESTED_OPTIONS);
        for (0..@as(usize, @intCast(count))) |index| {
            const object = begin + index * 24;
            const view = compat_runtime.libcppStringView(self, object) orelse continue;
            const name = self.guestMemoryConst(view.address, view.length) orelse continue;
            self.launch_options.request(name);
            std.debug.print("macho-processor: launch option acceleration retained positional option: {s}\n", .{name});
        }
    }

    fn handleGuestLogBridge(self: *MachOState) bool {
        if (self.internal_targets.guest_log_get_thread_buffer != 0 and
            self.regs.rip == self.internal_targets.guest_log_get_thread_buffer)
        {
            if (self.guest_log_buffer_address == 0) {
                self.guest_log_buffer_address = self.guestAlloc(GUEST_LOG_BUFFER_SIZE, 16) orelse return false;
                std.debug.print(
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

    fn handleCxxoptsSplitOptionNames(self: *MachOState) bool {
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
            std.debug.print(
                "macho-processor: cxxopts option-name fast path handled {d} call(s)\n",
                .{self.cxxopts_split_accelerations},
            );
        }
        self.regs.rax = output;
        self.regs.rip = self.pop();
        return true;
    }

    fn decodeAt(self: *MachOState) ?DecodedInsn {
        const off = self.addrToOffset(self.regs.rip) orelse return null;
        const cache_hash = self.regs.rip *% 0x9E37_79B9_7F4A_7C15;
        const cache_index: usize = @intCast(cache_hash >> DECODE_CACHE_HASH_SHIFT);
        const entry = &self.decode_cache[cache_index];
        var d: DecodedInsn = if (entry.rip == self.regs.rip and entry.code_generation == self.code_generation) blk: {
            self.decode_cache_hits += 1;
            break :blk entry.decoded;
        } else blk: {
            self.decode_cache_misses += 1;
            const decoded = decodeInsn(self.mem[off..]);
            entry.* = .{
                .rip = self.regs.rip,
                .code_generation = self.code_generation,
                .decoded = decoded,
            };
            break :blk decoded;
        };

        const addr_size: Size = if (d.has_0x67) .bits32 else .bits64;
        if (d.sib_has_index) {
            const index_val = self.regVal(d.sib_index_reg, addr_size);
            d.addr +%= index_val << @as(u6, d.sib_scale);
        }
        if (d.sib_has_base) {
            const base_val = self.regVal(d.sib_base_reg, addr_size);
            d.addr +%= base_val;
        }
        if (d.rip_relative) {
            d.addr +%= self.regs.rip + d.len;
        }

        return d;
    }

    fn step(self: *MachOState) bool {
        if (self.handleInternalCompatibility()) return !self.terminated;
        if (self.handleBoundImportThunk()) return !self.terminated;
        if (self.handleSyntheticRuntimeThunk()) return !self.terminated;
        if (self.handleStubHelperTransition()) {
            return !self.terminated;
        }
        if (!self.isExecutableAddress(self.regs.rip)) {
            if (self.pending_control_transfer) |context| {
                self.terminateForInvalidControlTransfer(context);
                self.dumpRecentTrace();
                return false;
            }
            std.debug.print(
                "macho-processor: invalid control-flow target rip=0x{x}; address is outside executable Mach-O segments\n",
                .{self.regs.rip},
            );
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
            return false;
        }
        self.pending_control_transfer = null;
        const decoded = self.decodeAt() orelse {
            const rip = self.regs.rip;
            std.debug.print("macho-processor: decode failed at rip=0x{x}\n", .{rip});
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                std.debug.print("macho-processor: decode failed file_offset=0x{x} bytes={any}\n", .{ file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: decode failed at unmapped address\n", .{});
            }
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.decode_failed);
            self.terminated = true;
            return false;
        };
        if (decoded.op == .invalid) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const mem_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            const rip = self.regs.rip;
            std.debug.print("macho-processor: invalid instruction at rip=0x{x}, mem_off=0x{x}, bytes: {any}\n", .{ rip, mem_off, mem_bytes });
            if (x64_decoder.capabilities.classifyRequirement(mem_bytes)) |requirement| {
                std.debug.print(
                    "macho-processor: ISA requirement: {s} encoding requires {s}; virtual profile={s}, advertised={}\n",
                    .{
                        @tagName(requirement.encoding),
                        x64_decoder.capabilities.featureLabel(requirement.feature),
                        self.cpu_profile.label(),
                        x64_decoder.capabilities.supports(self.cpu_profile, requirement.feature),
                    },
                );
            }
            if (self.fileOffsetForVaddr(rip)) |file_off| {
                const remaining = if (file_off < self.data.len) self.data.len - file_off else 0;
                const file_bytes = self.data[file_off..][0..@min(@as(usize, 16), remaining)];
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=0x{x} file_bytes={any}\n", .{ rip, file_off, file_bytes });
            } else {
                std.debug.print("macho-processor: invalid instruction source-map: rip=0x{x} file_off=<unmapped>\n", .{rip});
            }
            self.dumpRecentTrace();
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_instruction);
            self.terminated = true;
            return false;
        }
        self.recordTrace(decoded);
        if (self.verbose_trace) log.debug("rip=0x{x} op={s} len={d}", .{ self.regs.rip, @tagName(decoded.op), decoded.len });
        if (self.shouldTraceRIP(self.regs.rip)) {
            const mem_off = self.addrToOffset(self.regs.rip) orelse 0;
            const trace_bytes = self.mem[mem_off..][0..@min(@as(usize, 16), self.mem.len - mem_off)];
            log.info("target-trace: rip=0x{x} op={s} len={d} rsp=0x{x} rax=0x{x} rcx=0x{x} rdx=0x{x}", .{
                self.regs.rip,
                @tagName(decoded.op),
                decoded.len,
                self.regs.rsp,
                self.regs.rax,
                self.regs.rcx,
                self.regs.rdx,
            });
            log.info("target-trace-bytes: rip=0x{x} bytes={any}", .{ self.regs.rip, trace_bytes });
        }
        const old_rip = self.regs.rip;
        x64_interpreter.execute(self, decoded);
        if (!self.terminated and self.regs.rip == old_rip) {
            self.regs.rip +%= decoded.len;
        }
        return !self.terminated;
    }

    fn handleSyntheticRuntimeThunk(self: *MachOState) bool {
        const thunk = compat_runtime.syntheticThunk(self.regs.rip) orelse return false;
        const source_begin = self.regs.rsi;
        const source_end = self.regs.rdx;

        switch (thunk) {
            .ctype_toupper_char => self.regs.rax = std.ascii.toUpper(@as(u8, @truncate(self.regs.rsi))),
            .ctype_tolower_char => self.regs.rax = std.ascii.toLower(@as(u8, @truncate(self.regs.rsi))),
            .ctype_toupper_range, .ctype_tolower_range => {
                if (source_end < source_begin) {
                    self.regs.rax = source_begin;
                } else if (self.guestMemory(source_begin, source_end - source_begin)) |bytes| {
                    for (bytes) |*byte| {
                        byte.* = if (thunk == .ctype_toupper_range) std.ascii.toUpper(byte.*) else std.ascii.toLower(byte.*);
                    }
                    self.regs.rax = source_end;
                } else {
                    self.regs.rax = source_begin;
                }
            },
            .ctype_widen_char, .ctype_narrow_char => self.regs.rax = self.regs.rsi & 0xFF,
            .ctype_widen_range => {
                const count = source_end -| source_begin;
                const source = self.guestMemoryConst(source_begin, count);
                const destination = self.guestMemory(self.regs.rcx, count);
                if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
                self.regs.rax = source_end;
            },
            .ctype_narrow_range => {
                const count = source_end -| source_begin;
                const source = self.guestMemoryConst(source_begin, count);
                const destination = self.guestMemory(self.regs.r8, count);
                if (source != null and destination != null) std.mem.copyForwards(u8, destination.?, source.?);
                self.regs.rax = source_end;
            },
        }

        const return_address = self.pop();
        if (self.verbose_trace) std.debug.print("    [synthetic runtime] {s} -> rax=0x{x} return=0x{x}\n", .{ @tagName(thunk), self.regs.rax, return_address });
        if (return_address == 0) {
            self.faulted = true;
            self.exit_code = 127;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.invalid_control_flow_target);
            self.terminated = true;
        } else {
            self.regs.rip = return_address;
        }
        return true;
    }

    fn handleBoundImportThunk(self: *MachOState) bool {
        if (self.regs.rip < BOUND_IMPORT_THUNK_BASE) return false;
        for (self.bound_import_thunks) |thunk| {
            if (thunk.address != self.regs.rip) continue;
            self.handleDirectImportCall(.{
                .name = thunk.name,
                .dylib = thunk.dylib,
                .stub_address = thunk.address,
                .lazy_pointer_address = 0,
                .symbol_index = 0,
            });
            return true;
        }
        return false;
    }

    pub fn run(self: *MachOState) void {
        var steps: u64 = 0;
        while (!self.terminated and steps < self.max_steps) : (steps += 1) {
            self.executed_steps = steps;
            if (steps % 500000 == 0) {
                const symbol = self.metadata.nearestSymbol(self.regs.rip);
                const heap_summary = self.memory_forwarder.summary();
                self.startup.checkpoint(.{
                    .step = steps,
                    .rip = self.regs.rip,
                    .symbol = if (symbol) |resolved| resolved.name else "<unknown>",
                    .symbol_offset = if (symbol) |resolved| resolved.offset else 0,
                    .heap_next = self.heap_next,
                    .import_calls = self.import_resolver.total_calls,
                    .fs_open = self.fs_forwarder.open_count,
                    .fs_read = self.fs_forwarder.read_count,
                    .fs_write = self.fs_forwarder.write_count,
                    .heap_allocations = heap_summary.allocations,
                    .heap_live = heap_summary.live_allocations,
                    .options_seen = self.launch_options.registrations_seen,
                    .options_kept = self.launch_options.registrations_kept,
                    .options_skipped = self.launch_options.registrations_skipped,
                    .logging_lines = self.logging.emitted_lines,
                    .pthread_created = self.pthreads.created_threads,
                    .pthread_waits_collapsed = self.pthreads.collapsed_waits,
                    .diagnostic_text_runs = self.diagnostic_text.accelerations,
                    .diagnostic_text_lines = self.diagnostic_text.lines_retained,
                });
            }
            if (!self.step()) break;
        }
        if (steps >= self.max_steps) {
            log.warn("reached max steps ({d})", .{self.max_steps});
            self.faulted = true;
            self.exit_code = 124;
            self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.max_steps_reached);
            self.terminated = true;
        }
        if (self.unresolved_import_count != 0) {
            const current_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
            if (current_reason == .unknown or current_reason == .ret_stack_empty or current_reason == .exit_syscall) {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unresolved_import_result);
            }
        }
        const recorded_reason = exit_diagnostics.reasonFromValue(self.termination_reason);
        const normalized_reason = exit_diagnostics.normalizeReason(recorded_reason, self.unresolved_import_count);
        if (normalized_reason != recorded_reason) {
            std.debug.print(
                "macho-processor: diagnostics invariant repaired: reason={s} but unresolved_imports=0; reclassified={s}\n",
                .{ @tagName(recorded_reason), @tagName(normalized_reason) },
            );
            self.termination_reason = @intFromEnum(normalized_reason);
        }
        if (self.terminated and (self.exit_code != 0 or self.unresolved_import_count != 0)) {
            self.logExitDiagnostics();
        }
    }

    fn logDecodeCacheSummary(self: *const MachOState) void {
        const total = self.decode_cache_hits + self.decode_cache_misses;
        const hit_percent = if (total == 0) 0 else self.decode_cache_hits * 100 / total;
        std.debug.print(
            "macho-processor: decode cache: entries={d} hits={d} misses={d} hit_rate={d}% code_generation={d}\n",
            .{ self.decode_cache.len, self.decode_cache_hits, self.decode_cache_misses, hit_percent, self.code_generation },
        );
    }

    fn logExitDiagnostics(self: *const MachOState) void {
        const reason: exit_diagnostics.TerminationReason = exit_diagnostics.reasonFromValue(self.termination_reason);
        const attribution = exit_diagnostics.attribute(.{
            .reason = reason,
            .faulted = self.faulted,
            .unresolved_import_calls = self.unresolved_import_count,
        });
        var report = exit_diagnostics.ExitReport{
            .exit_code = self.exit_code,
            .reason = reason,
            .faulted = self.faulted,
            .rip = self.regs.rip,
            .regs = .{
                .rax = self.regs.rax,
                .rbx = self.regs.rbx,
                .rcx = self.regs.rcx,
                .rdx = self.regs.rdx,
                .rsi = self.regs.rsi,
                .rdi = self.regs.rdi,
                .rbp = self.regs.rbp,
                .rsp = self.regs.rsp,
                .r8 = self.regs.r8,
                .r9 = self.regs.r9,
                .r10 = self.regs.r10,
                .r11 = self.regs.r11,
                .r12 = self.regs.r12,
                .r13 = self.regs.r13,
                .r14 = self.regs.r14,
                .r15 = self.regs.r15,
            },
            .unresolved_import_calls = self.unresolved_import_count,
            .attribution = attribution,
            .execution_authoritative = attribution.authority == .authoritative,
            .control_transfer_failure = self.terminal_control_transfer,
        };

        if (self.isExecutableAddress(self.regs.rip)) {
            if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
                report.terminal_symbol = .{
                    .address = symbol.address,
                    .symbol = symbol.name,
                    .symbol_offset = symbol.offset,
                };
            }
        }

        if (self.cxx_exceptions.last_throw) |thrown| {
            var exception_report = exit_diagnostics.CxxExceptionReport{
                .object_address = thrown.object_address,
                .type_info_address = thrown.type_info_address,
                .type_name = self.cxxExceptionTypeName(thrown.type_info_address) orelse "",
                .type_symbol = self.diagnosticSymbol(thrown.type_info_address),
                .destructor_address = thrown.destructor_address,
                .destructor_symbol = self.diagnosticSymbol(thrown.destructor_address),
                .throw_site = self.diagnosticSymbol(thrown.caller_address),
                .message = self.cxxExceptionMessage(thrown.object_address) orelse "",
            };
            if (thrown.allocation) |allocation| {
                exception_report.allocation_matched = true;
                exception_report.allocation_size = allocation.object_size;
                exception_report.allocation_site = self.diagnosticSymbol(allocation.caller_address);
            }
            if (self.last_unwind_inspection) |inspection| {
                exception_report.unwinder_available = inspection.metadata_frames != 0;
                exception_report.unwind_frames = inspection.frame_count;
                if (inspection.handler) |handler| {
                    exception_report.handler_found = true;
                    exception_report.handler_address = handler.landing_pad;
                }
                exception_report.phase_two_supported = inspection.phase_two_supported;
            }
            report.cxx_exception = exception_report;
            report.detail = if (exception_report.phase_two_supported)
                "Rosette installed a verified Itanium phase-two landing-pad context before the later diagnostic stop."
            else
                "Rosette completed Itanium phase-one frame and catch inspection; this frame was not safe for phase-two context installation.";
        }

        const import_trace_count: usize = if (self.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else self.import_trace_index;
        if (import_trace_count > 0) {
            var import_trace_buf: [IMPORT_TRACE_BUFFER_LEN]exit_diagnostics.DependencyCall = undefined;
            for (0..import_trace_count) |i| {
                const idx = if (self.import_trace_filled)
                    (self.import_trace_index + i) % IMPORT_TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.import_trace_entries[idx];
                import_trace_buf[i] = .{
                    .symbol = entry.symbol,
                    .image = entry.dylib,
                    .stub_address = entry.stub_address,
                    .return_address = entry.return_address,
                    .synthetic_result = entry.synthetic_result,
                    .caller_symbol = entry.caller_symbol,
                    .caller_offset = entry.caller_offset,
                };
            }
            report.dependency_calls = import_trace_buf[0..import_trace_count];
            report.detail = "The interpreter did not execute these dynamic-library functions; the guest exit code is not authoritative.";
        }

        const trace_count: usize = if (self.trace_filled) TRACE_BUFFER_LEN else self.trace_index;
        if (trace_count > 0) {
            var trace_buf: [TRACE_BUFFER_LEN]exit_diagnostics.TraceEntry = undefined;
            for (0..trace_count) |i| {
                const idx = if (self.trace_filled)
                    (self.trace_index + i) % TRACE_BUFFER_LEN
                else
                    i;
                const entry = self.trace_entries[idx];
                trace_buf[i] = .{
                    .rip = entry.rip,
                    .op = @tagName(entry.op),
                    .len = entry.len,
                    .rsp = entry.rsp,
                    .rax = entry.rax,
                    .rcx = entry.rcx,
                    .rdx = entry.rdx,
                };
            }
            report.last_instructions = trace_buf[0..trace_count];
        }

        exit_diagnostics.logExitReport(report);
    }

    pub fn execute(self: *MachOState, d: DecodedInsn) void {
        switch (d.op) {
            .invalid => unreachable,
            .nop => {},
            .cmc => self.regs.rflags ^= RFL_CF,
            .clc => self.regs.rflags &= ~RFL_CF,
            .stc => self.regs.rflags |= RFL_CF,

            .mov_reg8_mem8 => {
                self.setReg(d.dst_reg, .bits8, self.readMemVal(d.addr, .bits8));
            },
            .mov_reg16_mem16 => {
                self.setReg(d.dst_reg, .bits16, self.readMemVal(d.addr, .bits16));
            },
            .mov_reg32_mem32 => {
                self.setReg(d.dst_reg, .bits32, self.readMemVal(d.addr, .bits32));
            },
            .mov_reg64_mem64 => {
                self.setReg(d.dst_reg, .bits64, self.readMemVal(d.addr, .bits64));
            },

            .mov_mem8_reg8 => {
                self.writeMemVal(d.addr, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_mem16_reg16 => {
                self.writeMemVal(d.addr, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_mem32_reg32 => {
                self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_mem64_reg64 => {
                self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .mov_reg_imm => {
                self.setReg(d.dst_reg, d.size, d.imm);
            },

            .mov_mem8_imm8 => {
                self.writeMemVal(d.addr, .bits8, d.imm);
            },
            .mov_mem16_imm16 => {
                self.writeMemVal(d.addr, .bits16, d.imm);
            },
            .mov_mem32_imm32 => {
                self.writeMemVal(d.addr, .bits32, d.imm);
            },
            .mov_mem64_imm32 => {
                self.writeMemVal(d.addr, .bits64, d.imm);
            },

            .mov_reg8_reg8 => {
                self.setReg(d.dst_reg, .bits8, self.regVal(d.src_reg, .bits8));
            },
            .mov_reg16_reg16 => {
                self.setReg(d.dst_reg, .bits16, self.regVal(d.src_reg, .bits16));
            },
            .mov_reg32_reg32 => {
                self.setReg(d.dst_reg, .bits32, self.regVal(d.src_reg, .bits32));
            },
            .mov_reg64_reg64 => {
                self.setReg(d.dst_reg, .bits64, self.regVal(d.src_reg, .bits64));
            },

            .add_accum_imm => self.executeAddRegImm(d, d.size),
            .or_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) | d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .adc_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
                const addend = d.imm +% carry;
                const result = input +% addend;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsAdd(input, addend, result, d.size);
            },
            .sbb_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                const carry: u64 = @intFromBool((self.regs.rflags & RFL_CF) != 0);
                const subtrahend = d.imm +% carry;
                const result = input -% subtrahend;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsSub(input, subtrahend, result, d.size);
            },
            .and_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) & d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .sub_accum_imm => self.executeSubRegImm(d, d.size),
            .xor_accum_imm => {
                const result = self.regVal(.al_ax_eax_rax, d.size) ^ d.imm;
                self.setReg(.al_ax_eax_rax, d.size, result);
                self.setFlagsLogic(result, d.size);
            },
            .cmp_accum_imm => {
                const input = self.regVal(.al_ax_eax_rax, d.size);
                self.setFlagsSub(input, d.imm, input -% d.imm, d.size);
            },

            .add_reg8_reg8, .add_reg16_reg16, .add_reg32_reg32, .add_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a +% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsAdd(a, b, r, sz);
            },
            .add_reg8_mem8, .add_reg16_mem16, .add_reg32_mem32, .add_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a +% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsAdd(a, b, r, sz);
            },
            .add_mem8_reg8, .add_mem16_reg16, .add_mem32_reg32, .add_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.add_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a +% b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsAdd(a, b, r, sz);
            },

            .add_reg8_imm8 => self.executeAddRegImm(d, .bits8),
            .add_reg16_imm8 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm8 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm8 => self.executeAddRegImm(d, .bits64),
            .add_reg16_imm32 => self.executeAddRegImm(d, .bits16),
            .add_reg32_imm32 => self.executeAddRegImm(d, .bits32),
            .add_reg64_imm32 => self.executeAddRegImm(d, .bits64),

            .sub_reg8_reg8, .sub_reg16_reg16, .sub_reg32_reg32, .sub_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_reg8_mem8, .sub_reg16_mem16, .sub_reg32_mem32, .sub_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a -% b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_mem8_reg8, .sub_mem16_reg16, .sub_mem32_reg32, .sub_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsSub(a, b, r, sz);
            },
            .sub_reg8_imm8, .sub_reg16_imm8, .sub_reg32_imm8, .sub_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.sub_reg8_imm8) + @intFromEnum(Size.bits8));
                self.executeSubRegImm(d, sz);
            },
            .sbb_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_imm8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = d.imm;
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .adc_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a +% b +% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsAdd(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },
            .sbb_reg8_mem8 => {
                const a = self.regVal(d.dst_reg, .bits8);
                const b = self.readMemVal(d.addr, .bits8);
                const cf = (self.regs.rflags & RFL_CF) != 0;
                const r = a -% b -% @as(u8, @intFromBool(cf));
                self.setReg(d.dst_reg, .bits8, r);
                self.setFlagsSub(a, b + @as(u8, @intFromBool(cf)), r, .bits8);
            },

            .and_reg8_reg8, .and_reg16_reg16, .and_reg32_reg32, .and_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_reg8_mem8, .and_reg16_mem16, .and_reg32_mem32, .and_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a & b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_mem8_reg8, .and_mem16_reg16, .and_mem32_reg32, .and_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.and_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .and_reg8_imm8, .and_reg16_imm8, .and_reg32_imm8, .and_reg64_imm8 => self.executeAndRegImm(d),
            .and_reg16_imm32, .and_reg32_imm32, .and_reg64_imm32 => self.executeAndRegImm(d),

            .or_reg8_reg8, .or_reg16_reg16, .or_reg32_reg32, .or_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a | b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_reg8_mem8, .or_reg16_mem16, .or_reg32_mem32, .or_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a | b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_mem8_reg8, .or_mem16_reg16, .or_mem32_reg32, .or_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a | b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_reg8_imm8, .or_reg16_imm8, .or_reg32_imm8, .or_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.or_reg8_imm8) + @intFromEnum(Size.bits8));
                const r = self.regVal(d.dst_reg, sz) | d.imm;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .or_mem8_imm8,
            .or_mem16_imm8,
            .or_mem32_imm8,
            .or_mem64_imm8,
            .or_mem16_imm32,
            .or_mem32_imm32,
            .or_mem64_imm32,
            => {
                const r = self.readMemVal(d.addr, d.size) | d.imm;
                self.writeMemVal(d.addr, d.size, r);
                self.setFlagsLogic(r, d.size);
            },

            .xor_reg8_reg8, .xor_reg16_reg16, .xor_reg32_reg32, .xor_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a ^ b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_reg8_mem8, .xor_reg16_mem16, .xor_reg32_mem32, .xor_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a ^ b;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_mem8_reg8, .xor_mem16_reg16, .xor_mem32_reg32, .xor_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a ^ b;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsLogic(r, sz);
            },
            .xor_reg8_imm8, .xor_reg16_imm8, .xor_reg32_imm8, .xor_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.xor_reg8_imm8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a ^ d.imm;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsLogic(r, sz);
            },

            .cmp_reg8_reg8, .cmp_reg16_reg16, .cmp_reg32_reg32, .cmp_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_reg8_mem8, .cmp_reg16_mem16, .cmp_reg32_mem32, .cmp_reg64_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_mem8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_mem8_reg8, .cmp_mem16_reg16, .cmp_mem32_reg32, .cmp_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a -% b;
                self.setFlagsSub(a, b, r, sz);
            },
            .cmp_reg8_imm8, .cmp_reg16_imm8, .cmp_reg32_imm8, .cmp_reg64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_reg8_imm8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a -% d.imm;
                self.setFlagsSub(a, d.imm, r, sz);
            },
            .cmp_mem8_imm8, .cmp_mem16_imm8, .cmp_mem32_imm8, .cmp_mem64_imm8 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.cmp_mem8_imm8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a -% d.imm;
                self.setFlagsSub(a, d.imm, r, sz);
            },

            .test_reg8_reg8, .test_reg16_reg16, .test_reg32_reg32, .test_reg64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_reg8_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setFlagsLogic(r, sz);
            },
            .test_mem8_reg8, .test_mem16_reg16, .test_mem32_reg32, .test_mem64_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.test_mem8_reg8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a & b;
                self.setFlagsLogic(r, sz);
            },
            .test_reg8_imm8, .test_reg16_imm16, .test_reg32_imm32, .test_reg64_imm32 => {
                const r = self.regVal(d.dst_reg, d.size) & d.imm;
                self.setFlagsLogic(r, d.size);
            },
            .test_mem8_imm8, .test_mem16_imm16, .test_mem32_imm32, .test_mem64_imm32 => {
                const r = self.readMemVal(d.addr, d.size) & d.imm;
                self.setFlagsLogic(r, d.size);
            },

            .inc_mem8, .inc_mem16, .inc_mem32, .inc_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a +% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .inc_reg8, .inc_reg16, .inc_reg32, .inc_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.inc_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a +% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, true);
            },
            .dec_mem8, .dec_mem16, .dec_mem32, .dec_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = a -% 1;
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },
            .dec_reg8, .dec_reg16, .dec_reg32, .dec_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.dec_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = a -% 1;
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsIncDec(a, r, sz, false);
            },

            .neg_reg8, .neg_reg16, .neg_reg32, .neg_reg64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_reg8) + @intFromEnum(Size.bits8));
                const a = self.regVal(d.dst_reg, sz);
                const r = (~a +% 1) & maskForSize(sz);
                self.setReg(d.dst_reg, sz, r);
                self.setFlagsSub(0, a, r, sz);
            },
            .neg_mem8, .neg_mem16, .neg_mem32, .neg_mem64 => {
                const sz: Size = @enumFromInt(@intFromEnum(d.op) - @intFromEnum(Op.neg_mem8) + @intFromEnum(Size.bits8));
                const a = self.readMemVal(d.addr, sz);
                const r = (~a +% 1) & maskForSize(sz);
                self.writeMemVal(d.addr, sz, r);
                self.setFlagsSub(0, a, r, sz);
            },
            .not_reg8, .not_reg16, .not_reg32, .not_reg64 => {
                self.setReg(d.dst_reg, d.size, ~self.regVal(d.dst_reg, d.size));
            },
            .not_mem8, .not_mem16, .not_mem32, .not_mem64 => {
                self.writeMemVal(d.addr, d.size, ~self.readMemVal(d.addr, d.size));
            },

            .push_reg => {
                self.push(self.regVal(d.dst_reg, .bits64));
            },
            .push_mem64 => {
                self.push(self.readMemVal(d.addr, .bits64));
            },
            .push_imm => {
                self.push(d.imm);
            },

            .pop_reg => {
                self.setReg(d.dst_reg, .bits64, self.pop());
            },
            .pop_mem64 => {
                self.writeMemVal(d.addr, .bits64, self.pop());
            },

            .lods => {
                const src_addr = self.regs.rsi;
                switch (d.size) {
                    .bits8 => self.setReg(.al_ax_eax_rax, .bits8, self.readMemVal(src_addr, .bits8)),
                    .bits16 => self.setReg(.al_ax_eax_rax, .bits16, self.readMemVal(src_addr, .bits16)),
                    .bits32 => self.setReg(.al_ax_eax_rax, .bits32, self.readMemVal(src_addr, .bits32)),
                    .bits64 => self.setReg(.al_ax_eax_rax, .bits64, self.readMemVal(src_addr, .bits64)),
                }
                const stride: u64 = switch (d.size) {
                    .bits8 => 1,
                    .bits16 => 2,
                    .bits32 => 4,
                    .bits64 => 8,
                };
                if ((self.regs.rflags & RFL_DF) != 0) {
                    self.regs.rsi -|= stride;
                } else {
                    self.regs.rsi +|= stride;
                }
            },

            .call_rel32 => {
                const from_rip = self.regs.rip;
                const target = d.addr;
                const return_addr = self.regs.rip + d.len;
                self.pending_control_transfer = .{
                    .kind = "call_rel32",
                    .instruction_address = from_rip,
                    .target_address = target,
                    .return_address = return_addr,
                };
                self.push(return_addr);
                self.regs.rip = target;
                self.logControlFlow("call_rel32", from_rip, target, d.len, return_addr);
            },
            .call_reg64 => {
                const from_rip = self.regs.rip;
                const target = self.regVal(d.dst_reg, .bits64);
                const return_addr = self.regs.rip + d.len;
                if (target == 0) {
                    self.logControlFlow("call_reg64_null", from_rip, target, d.len, return_addr);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "call_reg64_null",
                        .instruction_address = from_rip,
                        .target_address = target,
                        .return_address = return_addr,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "call_reg64",
                        .instruction_address = from_rip,
                        .target_address = target,
                        .return_address = return_addr,
                    };
                    self.push(return_addr);
                    self.regs.rip = target;
                    self.logControlFlow("call_reg64", from_rip, target, d.len, return_addr);
                }
            },
            .call_mem64 => {
                const from_rip = self.regs.rip;
                const target = self.readMemVal(d.addr, .bits64);
                const return_addr = self.regs.rip + d.len;
                if (target == 0) {
                    self.logControlFlow("call_mem64_null", from_rip, target, d.len, return_addr);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "call_mem64_null",
                        .instruction_address = from_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                        .return_address = return_addr,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "call_mem64",
                        .instruction_address = from_rip,
                        .operand_address = d.addr,
                        .target_address = target,
                        .return_address = return_addr,
                    };
                    self.push(return_addr);
                    self.regs.rip = target;
                    self.logControlFlow("call_mem64", from_rip, target, d.len, return_addr);
                }
            },

            .ret => {
                if (d.imm > 0) {
                    self.regs.rsp +|= d.imm;
                }
                const ret_addr = self.pop();
                if (ret_addr == 0) {
                    self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.ret_stack_empty);
                    self.terminated = true;
                    self.exit_code = self.regs.rax;
                    return;
                }
                self.logControlFlow("ret", self.regs.rip, ret_addr, d.len, null);
                self.regs.rip = ret_addr;
            },

            .jmp_rel8 => {
                self.pending_control_transfer = .{
                    .kind = "jmp_rel8",
                    .instruction_address = self.regs.rip,
                    .target_address = d.addr,
                };
                self.logControlFlow("jmp", self.regs.rip, d.addr, d.len, null);
                self.regs.rip = d.addr;
            },
            .jmp_reg64 => {
                const target = self.regVal(d.dst_reg, .bits64);
                if (target == 0) {
                    self.logControlFlow("jmp_reg64_null", self.regs.rip, target, d.len, null);
                    self.terminateForInvalidControlTransfer(.{
                        .kind = "jmp_reg64_null",
                        .instruction_address = self.regs.rip,
                        .target_address = target,
                    });
                } else {
                    self.pending_control_transfer = .{
                        .kind = "jmp_reg64",
                        .instruction_address = self.regs.rip,
                        .target_address = target,
                    };
                    self.logControlFlow("jmp_reg64", self.regs.rip, target, d.len, null);
                    self.regs.rip = target;
                }
            },
            .jmp_mem64 => {
                const target = self.readMemVal(d.addr, .bits64);
                if (target == 0) {
                    if (self.metadata.importAtStub(self.regs.rip)) |imported| {
                        self.pending_import_stub_rip = null;
                        self.handleDirectImportCall(imported);
                    } else {
                        self.logControlFlow("jmp_mem64_null", self.regs.rip, target, d.len, null);
                        self.terminateForInvalidControlTransfer(.{
                            .kind = "jmp_mem64_null",
                            .instruction_address = self.regs.rip,
                            .operand_address = d.addr,
                            .target_address = target,
                        });
                    }
                } else {
                    self.pending_import_stub_rip = if (self.metadata.importAtStub(self.regs.rip) != null) self.regs.rip else null;
                    self.pending_control_transfer = .{
                        .kind = "jmp_mem64",
                        .instruction_address = self.regs.rip,
                        .operand_address = d.addr,
                        .target_address = target,
                    };
                    self.logControlFlow("jmp_mem64", self.regs.rip, target, d.len, null);
                    self.regs.rip = target;
                }
            },

            .jcc_rel8, .jcc_rel32 => {
                const condMet = x64_decoder.evalCond(self.regs.rflags, d.cond);
                if (condMet) {
                    self.logControlFlow("jcc_taken", self.regs.rip, d.addr, d.len, null);
                    self.regs.rip = d.addr;
                }
            },

            .bsf_reg_reg,
            .bsf_reg_mem,
            .bsr_reg_reg,
            .bsr_reg_mem,
            .tzcnt_reg_reg,
            .tzcnt_reg_mem,
            .lzcnt_reg_reg,
            .lzcnt_reg_mem,
            => self.executeBitScan(d),

            .bswap_reg => self.setReg(d.dst_reg, d.size, x64_decoder.byteSwap(d.size, self.regVal(d.dst_reg, d.size))),

            .rol_reg_cl,
            .rol_mem_cl,
            .ror_reg_cl,
            .ror_mem_cl,
            .rol_reg_imm,
            .rol_mem_imm,
            .ror_reg_imm,
            .ror_mem_imm,
            => self.executeRotate(d),

            .shl_reg_cl, .shl_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_cl, .shr_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_cl, .sar_mem_cl => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_cl;
                const count = self.regVal(.cl_cx_ecx_rcx, .bits8) & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shr_reg_imm, .shr_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shr_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) >> @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .shl_reg_imm, .shl_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .shl_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = (a & maskForSize(sz)) << @as(u6, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },
            .sar_reg_imm, .sar_mem_imm => {
                const sz = d.size;
                const is_mem = d.op == .sar_mem_imm;
                const count = d.imm & @as(u64, if (sz == .bits64) 0x3F else 0x1F);
                const a = if (is_mem) self.readMemVal(d.addr, sz) else self.regVal(d.dst_reg, sz);
                const r = arithmeticShiftRight(a, sz, @intCast(count));
                if (is_mem) self.writeMemVal(d.addr, sz, r) else self.setReg(d.dst_reg, sz, r);
            },

            .mul_reg8 => {
                const a = self.regVal(.al_ax_eax_rax, .bits8);
                const b = self.regVal(d.dst_reg, .bits8);
                const r = a * b;
                self.setReg(.al_ax_eax_rax, .bits16, r);
                self.setFlag(RFL_CF, r >> 8 != 0);
                self.setFlag(RFL_OF, r >> 8 != 0);
            },
            .mul_reg16 => {
                const a = self.regVal(.al_ax_eax_rax, .bits16);
                const b = self.regVal(d.dst_reg, .bits16);
                const r: u32 = @as(u32, @truncate(a)) * @as(u32, @truncate(b));
                self.setReg(.al_ax_eax_rax, .bits16, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits16, @truncate(r >> 16));
                self.setFlag(RFL_CF, r >> 16 != 0);
                self.setFlag(RFL_OF, r >> 16 != 0);
            },
            .mul_reg32 => {
                const a = self.regVal(.al_ax_eax_rax, .bits32);
                const b = self.regVal(d.dst_reg, .bits32);
                const r: u64 = @as(u64, a) * @as(u64, b);
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(r));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(r >> 32));
                self.setFlag(RFL_CF, r >> 32 != 0);
                self.setFlag(RFL_OF, r >> 32 != 0);
            },
            .mul_reg64 => {
                const a = self.regs.rax;
                const b = self.regVal(d.dst_reg, .bits64);
                @setRuntimeSafety(false);
                const r = @as(u128, a) * @as(u128, b);
                self.regs.rax = @truncate(r);
                self.regs.rdx = @truncate(r >> 64);
                self.setFlag(RFL_CF, self.regs.rdx != 0);
                self.setFlag(RFL_OF, self.regs.rdx != 0);
            },

            .div_mem16, .div_reg16 => {
                const divisor: u16 = @truncate(if (d.op == .div_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16));
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u16)) return self.raiseDivideError();
                self.setReg(.al_ax_eax_rax, .bits16, quotient);
                self.setReg(.dl_dx_edx_rdx, .bits16, dividend % divisor);
            },
            .div_mem32, .div_reg32 => {
                const divisor: u32 = @truncate(if (d.op == .div_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32));
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u32)) return self.raiseDivideError();
                self.setReg(.al_ax_eax_rax, .bits32, quotient);
                self.setReg(.dl_dx_edx_rdx, .bits32, dividend % divisor);
            },
            .div_mem64, .div_reg64 => {
                const divisor = if (d.op == .div_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
                if (divisor == 0) return self.raiseDivideError();
                const dividend = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
                const quotient = dividend / divisor;
                if (quotient > std.math.maxInt(u64)) return self.raiseDivideError();
                self.regs.rax = @truncate(quotient);
                self.regs.rdx = @truncate(dividend % divisor);
            },
            .idiv_mem16, .idiv_reg16 => {
                const raw_divisor = if (d.op == .idiv_mem16) self.readMemVal(d.addr, .bits16) else self.regVal(d.dst_reg, .bits16);
                const divisor: i16 = @bitCast(@as(u16, @truncate(raw_divisor)));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u32, @truncate(self.regs.rdx)) << 16) | @as(u16, @truncate(self.regs.rax));
                const dividend: i32 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i32, divisor));
                if (quotient < std.math.minInt(i16) or quotient > std.math.maxInt(i16)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i32, divisor));
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @intCast(quotient)))));
                self.setReg(.dl_dx_edx_rdx, .bits16, @as(u16, @bitCast(@as(i16, @intCast(remainder)))));
            },
            .idiv_mem32, .idiv_reg32 => {
                const raw_divisor = if (d.op == .idiv_mem32) self.readMemVal(d.addr, .bits32) else self.regVal(d.dst_reg, .bits32);
                const divisor: i32 = @bitCast(@as(u32, @truncate(raw_divisor)));
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u64, @truncate(self.regs.rdx)) << 32) | @as(u32, @truncate(self.regs.rax));
                const dividend: i64 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i64, divisor));
                if (quotient < std.math.minInt(i32) or quotient > std.math.maxInt(i32)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i64, divisor));
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @intCast(quotient)))));
                self.setReg(.dl_dx_edx_rdx, .bits32, @as(u32, @bitCast(@as(i32, @intCast(remainder)))));
            },
            .idiv_mem64, .idiv_reg64 => {
                const raw_divisor = if (d.op == .idiv_mem64) self.readMemVal(d.addr, .bits64) else self.regVal(d.dst_reg, .bits64);
                const divisor: i64 = @bitCast(raw_divisor);
                if (divisor == 0) return self.raiseDivideError();
                const dividend_bits = (@as(u128, self.regs.rdx) << 64) | self.regs.rax;
                const dividend: i128 = @bitCast(dividend_bits);
                const quotient = @divTrunc(dividend, @as(i128, divisor));
                if (quotient < std.math.minInt(i64) or quotient > std.math.maxInt(i64)) return self.raiseDivideError();
                const remainder = @rem(dividend, @as(i128, divisor));
                self.regs.rax = @bitCast(@as(i64, @intCast(quotient)));
                self.regs.rdx = @bitCast(@as(i64, @intCast(remainder)));
            },
            .imul_reg64_reg64, .imul_reg32_reg32 => {
                const sz = if (d.op == .imul_reg64_reg64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.regVal(d.src_reg, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64, .imul_reg32_mem32 => {
                const sz = if (d.op == .imul_reg64_mem64) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const b = self.readMemVal(d.addr, sz);
                const r = a *% b;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_reg64_imm8, .imul_reg32_reg32_imm8 => {
                const sz = if (d.op == .imul_reg64_reg64_imm8) Size.bits64 else Size.bits32;
                const a = self.regVal(d.dst_reg, sz);
                const r = a *% d.imm;
                self.setReg(d.dst_reg, sz, r);
            },
            .imul_reg64_mem64_imm8, .imul_reg32_mem32_imm8 => {
                const sz = if (d.op == .imul_reg64_mem64_imm8) Size.bits64 else Size.bits32;
                const a = self.readMemVal(d.addr, sz);
                const r = a *% d.imm;
                self.setReg(d.dst_reg, sz, r);
            },

            .lea_reg_mem => {
                self.setReg(d.dst_reg, d.size, d.addr);
            },

            .movzx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movzx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                self.setReg(d.dst_reg, d.size, val);
            },
            .movsx_reg32_mem8 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits8)
                else
                    self.readMemVal(d.addr, .bits8);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsx_reg32_mem16 => {
                const val = if (d.is_reg_form)
                    self.regVal(d.src_reg, .bits16)
                else
                    self.readMemVal(d.addr, .bits16);
                const signed_val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
                self.setReg(d.dst_reg, d.size, signed_val);
            },
            .movsxd_reg64_reg32 => {
                const val = self.regVal(d.src_reg, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },
            .movsxd_reg64_mem32 => {
                const val = self.readMemVal(d.addr, .bits32);
                const signed_val = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(val)))))));
                self.setReg(d.dst_reg, .bits64, signed_val);
            },

            .cbw => {
                self.setReg(.al_ax_eax_rax, .bits16, @as(u16, @bitCast(@as(i16, @as(i8, @bitCast(@as(u8, @truncate(self.regs.rax))))))));
            },
            .cwde => {
                self.setReg(.al_ax_eax_rax, .bits32, @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(self.regs.rax))))))));
            },
            .cdqe => {
                self.regs.rax = @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(@as(u32, @truncate(self.regs.rax)))))));
            },
            .cwd => {
                const val = self.regVal(.al_ax_eax_rax, .bits16);
                const sign = @as(u16, @bitCast(@as(i16, @intCast(val)))) >> 15;
                self.setReg(.dl_dx_edx_rdx, .bits16, if (sign != 0) 0xFFFF else 0);
            },
            .cdq => {
                const val = self.regVal(.al_ax_eax_rax, .bits32);
                const sign = @as(u32, @bitCast(@as(i32, @intCast(val)))) >> 31;
                self.setReg(.dl_dx_edx_rdx, .bits32, if (sign != 0) 0xFFFF_FFFF else 0);
            },
            .cqo => {
                const val = self.regs.rax;
                const sign = (val & 0x8000_0000_0000_0000) != 0;
                self.regs.rdx = if (sign) 0xFFFF_FFFF_FFFF_FFFF else 0;
            },

            .cmovcc_reg_reg => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.regVal(d.src_reg, d.size));
                }
            },
            .cmovcc_reg_mem => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, d.size, self.readMemVal(d.addr, d.size));
                }
            },

            .setcc_reg8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.setReg(d.dst_reg, .bits8, 1);
                } else {
                    self.setReg(d.dst_reg, .bits8, 0);
                }
            },
            .setcc_mem8 => {
                if (x64_decoder.evalCond(self.regs.rflags, d.cond)) {
                    self.writeMemVal(d.addr, .bits8, 1);
                } else {
                    self.writeMemVal(d.addr, .bits8, 0);
                }
            },

            .cmpxchg_mem32_reg32 => {
                const expected = self.regVal(.al_ax_eax_rax, .bits32);
                const actual = self.readMemVal(d.addr, .bits32);
                if (expected == actual) {
                    self.writeMemVal(d.addr, .bits32, self.regVal(d.src_reg, .bits32));
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.setReg(.al_ax_eax_rax, .bits32, actual);
                    self.setFlag(RFL_ZF, false);
                }
            },
            .cmpxchg_mem64_reg64 => {
                const expected = self.regs.rax;
                const actual = self.readMemVal(d.addr, .bits64);
                if (expected == actual) {
                    self.writeMemVal(d.addr, .bits64, self.regVal(d.src_reg, .bits64));
                    self.setFlag(RFL_ZF, true);
                } else {
                    self.regs.rax = actual;
                    self.setFlag(RFL_ZF, false);
                }
            },

            .xchg_mem32_reg32 => {
                const a = self.readMemVal(d.addr, .bits32);
                const b = self.regVal(d.src_reg, .bits32);
                self.writeMemVal(d.addr, .bits32, b);
                self.setReg(d.src_reg, .bits32, a);
            },
            .xchg_mem64_reg64 => {
                const a = self.readMemVal(d.addr, .bits64);
                const b = self.regVal(d.src_reg, .bits64);
                self.writeMemVal(d.addr, .bits64, b);
                self.setReg(d.src_reg, .bits64, a);
            },
            .xadd_mem32_reg32, .xadd_mem64_reg64 => {
                const sz: Size = if (d.op == .xadd_mem64_reg64) .bits64 else .bits32;
                const old_mem = self.readMemVal(d.addr, sz);
                const old_reg = self.regVal(d.src_reg, sz);
                const result = old_mem +% old_reg;
                self.writeMemVal(d.addr, sz, result);
                self.setReg(d.src_reg, sz, old_mem);
                self.setFlagsAdd(old_mem, old_reg, result, sz);
            },

            .xorps_xmm_xmm => {
                const dst = d.xmm_dst;
                const src = d.xmm_src;
                for (&self.xmm[dst], self.xmm[src]) |*d8, s8| d8.* = d8.* ^ s8;
            },
            .movups_xmm_xmm, .movaps_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
            },
            .movups_xmm_mem, .movaps_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
            },
            .movups_mem_xmm, .movaps_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .vmovd_xmm_reg32, .vmovd_xmm_mem32 => {
                const value: u32 = @truncate(if (d.op == .vmovd_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits32));
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], value, .little);
            },
            .vmovq_xmm_reg64, .vmovq_xmm_mem64 => {
                const value = if (d.op == .vmovq_xmm_reg64)
                    self.regVal(d.src_reg, .bits64)
                else
                    self.readMemVal(d.addr, .bits64);
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], value, .little);
            },
            .vmovq_reg64_xmm, .vmovq_mem64_xmm => {
                const value = std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little);
                if (d.op == .vmovq_reg64_xmm) {
                    self.setReg(d.dst_reg, .bits64, value);
                } else {
                    self.writeMemVal(d.addr, .bits64, value);
                }
            },
            .vpinsrb_xmm_xmm_reg32, .vpinsrb_xmm_xmm_mem8 => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                const value: u8 = @truncate(if (d.op == .vpinsrb_xmm_xmm_reg32)
                    self.regVal(d.src_reg, .bits32)
                else
                    self.readMemVal(d.addr, .bits8));
                self.xmm[d.xmm_dst][@intCast(d.imm & 0x0F)] = value;
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vpshufb => {
                const source_low = self.xmm[d.xmm_src];
                const mask_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = shuffleBytes(source_low, mask_low);
                if (d.vector_256) {
                    const source_high = self.ymm_hi[d.xmm_src];
                    const mask_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = shuffleBytes(source_high, mask_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vpcmpeqd => {
                const rhs_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = compareEqualDwords(self.xmm[d.xmm_src], rhs_low);
                if (d.vector_256) {
                    const rhs_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = compareEqualDwords(self.ymm_hi[d.xmm_src], rhs_high);
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vmovdqu_xmm_xmm, .vmovdqa_xmm_xmm, .vmovups_xmm_xmm, .vmovaps_xmm_xmm, .vmovupd_xmm_xmm, .vmovapd_xmm_xmm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovdqu_xmm_mem, .vmovdqa_xmm_mem, .vmovups_xmm_mem, .vmovaps_xmm_mem, .vmovupd_xmm_mem, .vmovapd_xmm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vmovdqu_mem_xmm, .vmovdqa_mem_xmm, .vmovups_mem_xmm, .vmovaps_mem_xmm, .vmovupd_mem_xmm, .vmovapd_mem_xmm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
            },
            .vmovdqu_ymm_ymm, .vmovdqa_ymm_ymm, .vmovups_ymm_ymm, .vmovaps_ymm_ymm, .vmovupd_ymm_ymm, .vmovapd_ymm_ymm => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                self.ymm_hi[d.xmm_dst] = self.ymm_hi[d.xmm_src];
            },
            .vmovdqu_ymm_mem, .vmovdqa_ymm_mem, .vmovups_ymm_mem, .vmovaps_ymm_mem, .vmovupd_ymm_mem, .vmovapd_ymm_mem => {
                self.xmm[d.xmm_dst] = self.readMem128(d.addr);
                self.ymm_hi[d.xmm_dst] = self.readMem128(d.addr + 16);
            },
            .vmovdqu_mem_ymm, .vmovdqa_mem_ymm, .vmovups_mem_ymm, .vmovaps_mem_ymm, .vmovupd_mem_ymm, .vmovapd_mem_ymm => {
                self.writeMem128(d.addr, self.xmm[d.xmm_src]);
                self.writeMem128(d.addr + 16, self.ymm_hi[d.xmm_src]);
            },
            .vmovss_xmm_mem => {
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @truncate(self.readMemVal(d.addr, .bits32)), .little);
            },
            .vmovss_mem_xmm => {
                self.writeMemVal(d.addr, .bits32, std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
            },
            .vmovsd_xmm_mem => {
                @memset(&self.xmm[d.xmm_dst], 0);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], self.readMemVal(d.addr, .bits64), .little);
            },
            .vmovsd_mem_xmm => {
                self.writeMemVal(d.addr, .bits64, std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
            },
            .vzeroupper => {
                for (&self.ymm_hi) |*upper| @memset(upper, 0);
            },
            .vcvtsi2ss_xmm_reg, .vcvtsi2ss_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2ss_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                const converted: f32 = @floatFromInt(integer);
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(converted), .little);
            },
            .vcvtsi2sd_xmm_reg, .vcvtsi2sd_xmm_mem => {
                self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
                @memset(&self.ymm_hi[d.xmm_dst], 0);
                const integer: i64 = if (d.size == .bits64)
                    @bitCast(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits64) else self.readMemVal(d.addr, .bits64))
                else
                    @as(i32, @bitCast(@as(u32, @truncate(if (d.op == .vcvtsi2sd_xmm_reg) self.regVal(d.src_reg, .bits32) else self.readMemVal(d.addr, .bits32)))));
                const converted: f64 = @floatFromInt(integer);
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(converted), .little);
            },
            .vaddss, .vmulss, .vsubss, .vdivss => {
                self.executeVexScalarF32(d, vexArithmeticForOp(d.op));
            },
            .vaddsd, .vmulsd, .vsubsd, .vdivsd => {
                self.executeVexScalarF64(d, vexArithmeticForOp(d.op));
            },
            .vaddps, .vmulps, .vsubps, .vdivps => {
                self.executeVexPackedF32(d, vexArithmeticForOp(d.op));
            },
            .vaddpd, .vmulpd, .vsubpd, .vdivpd => {
                self.executeVexPackedF64(d, vexArithmeticForOp(d.op));
            },
            .vucomiss => {
                const lhs: f32 = @bitCast(std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little));
                const rhs_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                self.setVexComparisonFlags(lhs, @as(f32, @bitCast(rhs_bits)));
            },
            .vucomisd => {
                const lhs: f64 = @bitCast(std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little));
                const rhs_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                self.setVexComparisonFlags(lhs, @as(f64, @bitCast(rhs_bits)));
            },
            .vroundss => {
                const source1 = self.xmm[d.xmm_src];
                const source2_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                self.xmm[d.xmm_dst] = source1;
                std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(roundVexFloat(f32, @bitCast(source2_bits), @truncate(d.imm))), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vroundsd => {
                const source1 = self.xmm[d.xmm_src];
                const source2_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                self.xmm[d.xmm_dst] = source1;
                std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(roundVexFloat(f64, @bitCast(source2_bits), @truncate(d.imm))), .little);
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            },
            .vroundps => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = roundVexPackedF32(source_low, @truncate(d.imm));
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = roundVexPackedF32(source_high, @truncate(d.imm));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vroundpd => {
                const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
                self.xmm[d.xmm_dst] = roundVexPackedF64(source_low, @truncate(d.imm));
                if (d.vector_256) {
                    const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
                    self.ymm_hi[d.xmm_dst] = roundVexPackedF64(source_high, @truncate(d.imm));
                } else {
                    @memset(&self.ymm_hi[d.xmm_dst], 0);
                }
            },
            .vcvttss2si, .vcvtss2si => {
                const source_bits = if (d.is_reg_form)
                    std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little)
                else
                    @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
                const source: f32 = @bitCast(source_bits);
                self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f32, source, d.size, d.op == .vcvttss2si));
            },
            .vcvttsd2si, .vcvtsd2si => {
                const source_bits = if (d.is_reg_form)
                    std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little)
                else
                    self.readMemVal(d.addr, .bits64);
                const source: f64 = @bitCast(source_bits);
                self.setReg(d.dst_reg, d.size, convertVexFloatToSigned(f64, source, d.size, d.op == .vcvttsd2si));
            },
            .vandps, .vandpd, .vandnps, .vandnpd, .vorps, .vorpd, .vxorps, .vxorpd => {
                self.executeVexBitwise(d, vexBitwiseForOp(d.op));
            },

            .syscall => {
                self.dispatchMacOSSyscall(
                    self.regs.rdi,
                    self.regs.rsi,
                    self.regs.rdx,
                    self.regs.r10,
                    self.regs.r8,
                    self.regs.r9,
                );
            },

            .cpuid => {
                const leaf: u32 = @truncate(self.regs.rax);
                const subleaf: u32 = @truncate(self.regs.rcx);
                const result = x64_decoder.capabilities.cpuid(self.cpu_profile, leaf, subleaf);
                log.info(
                    "cpuid: leaf=0x{x} subleaf=0x{x} -> eax=0x{x} ebx=0x{x} ecx=0x{x} edx=0x{x}",
                    .{ leaf, subleaf, result.eax, result.ebx, result.ecx, result.edx },
                );
                self.setReg(.al_ax_eax_rax, .bits32, result.eax);
                self.setReg(.bl_bx_ebx_rbx, .bits32, result.ebx);
                self.setReg(.cl_cx_ecx_rcx, .bits32, result.ecx);
                self.setReg(.dl_dx_edx_rdx, .bits32, result.edx);
            },

            .xgetbv => {
                const xcr0 = if (@as(u32, @truncate(self.regs.rcx)) == 0)
                    x64_decoder.capabilities.xcr0(self.cpu_profile)
                else
                    0;
                log.info("xgetbv: xcr=0x{x} -> xcr0=0x{x} profile={s}", .{ self.regs.rcx, xcr0, self.cpu_profile.label() });
                self.setReg(.al_ax_eax_rax, .bits32, @truncate(xcr0));
                self.setReg(.dl_dx_edx_rdx, .bits32, @truncate(xcr0 >> 32));
            },

            .hlt => {
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.hlt);
                self.terminated = true;
                self.exit_code = self.regs.rax;
            },

            else => {
                log.warn("unimplemented instruction: {s} at rip=0x{x}", .{ @tagName(d.op), self.regs.rip });
                self.faulted = true;
                self.exit_code = 127;
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.unimplemented_instruction);
                self.terminated = true;
            },
        }
    }

    fn executeBitScan(self: *MachOState, d: DecodedInsn) void {
        const is_memory = switch (d.op) {
            .bsf_reg_mem, .bsr_reg_mem, .tzcnt_reg_mem, .lzcnt_reg_mem => true,
            else => false,
        };
        const kind: BitScanKind = switch (d.op) {
            .bsf_reg_reg, .bsf_reg_mem => .bsf,
            .bsr_reg_reg, .bsr_reg_mem => .bsr,
            .tzcnt_reg_reg, .tzcnt_reg_mem => .tzcnt,
            .lzcnt_reg_reg, .lzcnt_reg_mem => .lzcnt,
            else => unreachable,
        };
        const source = if (is_memory) self.readMemVal(d.addr, d.size) else self.regVal(d.src_reg, d.size);
        const result = bitScan(d.size, kind, source);

        if (result.write_destination) self.setReg(d.dst_reg, d.size, result.value);
        self.setFlag(RFL_ZF, result.zero_flag);
        if (result.carry_flag) |carry| self.setFlag(RFL_CF, carry);
    }

    fn executeRotate(self: *MachOState, d: DecodedInsn) void {
        const is_mem = switch (d.op) {
            .rol_mem_cl, .ror_mem_cl, .rol_mem_imm, .ror_mem_imm => true,
            else => false,
        };
        const rotate_left = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .rol_reg_imm, .rol_mem_imm => true,
            else => false,
        };
        const uses_cl = switch (d.op) {
            .rol_reg_cl, .rol_mem_cl, .ror_reg_cl, .ror_mem_cl => true,
            else => false,
        };
        const raw_count = if (uses_cl) self.regVal(.cl_cx_ecx_rcx, .bits8) else d.imm;
        const masked_count = raw_count & @as(u64, if (d.size == .bits64) 0x3F else 0x1F);
        const width: u64 = bitWidth(d.size);
        const count: u6 = @intCast(masked_count % width);
        if (count == 0) return;

        const mask = maskForSize(d.size);
        const old = (if (is_mem) self.readMemVal(d.addr, d.size) else self.regVal(d.dst_reg, d.size)) & mask;
        const inverse: u6 = @intCast(width - count);
        const result = if (rotate_left)
            ((old << count) | (old >> inverse)) & mask
        else
            ((old >> count) | (old << inverse)) & mask;

        if (is_mem) self.writeMemVal(d.addr, d.size, result) else self.setReg(d.dst_reg, d.size, result);
        if (rotate_left) {
            const carry = (result & 1) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) self.setFlag(RFL_OF, ((result & signBitForSize(d.size)) != 0) != carry);
        } else {
            const carry = (result & signBitForSize(d.size)) != 0;
            self.setFlag(RFL_CF, carry);
            if (count == 1) {
                const next_sign = (result & (signBitForSize(d.size) >> 1)) != 0;
                self.setFlag(RFL_OF, carry != next_sign);
            }
        }
    }

    fn executeVexScalarF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1 = self.xmm[d.xmm_src];
        const source2_bits = if (d.is_reg_form)
            std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
        else
            @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
        const source1_value: f32 = @bitCast(std.mem.readInt(u32, source1[0..4], .little));
        const source2_value: f32 = @bitCast(source2_bits);

        self.xmm[d.xmm_dst] = source1;
        std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(applyVexArithmetic(f32, source1_value, source2_value, operation)), .little);
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexScalarF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1 = self.xmm[d.xmm_src];
        const source2_bits = if (d.is_reg_form)
            std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
        else
            self.readMemVal(d.addr, .bits64);
        const source1_value: f64 = @bitCast(std.mem.readInt(u64, source1[0..8], .little));
        const source2_value: f64 = @bitCast(source2_bits);

        self.xmm[d.xmm_dst] = source1;
        std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(applyVexArithmetic(f64, source1_value, source2_value, operation)), .little);
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }

    fn executeVexPackedF32(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexPackedF32(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexPackedF32(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn executeVexPackedF64(self: *MachOState, d: DecodedInsn, operation: VexArithmetic) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexPackedF64(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexPackedF64(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn setVexComparisonFlags(self: *MachOState, lhs: anytype, rhs: @TypeOf(lhs)) void {
        self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
        if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
            self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
        } else if (lhs < rhs) {
            self.regs.rflags |= RFL_CF;
        } else if (lhs == rhs) {
            self.regs.rflags |= RFL_ZF;
        }
    }

    fn executeVexBitwise(self: *MachOState, d: DecodedInsn, operation: VexBitwise) void {
        const source1_low = self.xmm[d.xmm_src];
        const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
        self.xmm[d.xmm_dst] = applyVexBitwise(source1_low, source2_low, operation);

        if (d.vector_256) {
            const source1_high = self.ymm_hi[d.xmm_src];
            const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
            self.ymm_hi[d.xmm_dst] = applyVexBitwise(source1_high, source2_high, operation);
        } else {
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        }
    }

    fn executeAddRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        const a = self.regVal(d.dst_reg, sz);
        const r = a +% d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsAdd(a, d.imm, r, sz);
    }

    fn raiseDivideError(self: *MachOState) void {
        self.faulted = true;
        self.terminated = true;
        self.exit_code = 136;
        self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.divide_by_zero);
    }

    fn executeSubRegImm(self: *MachOState, d: DecodedInsn, sz: Size) void {
        const a = self.regVal(d.dst_reg, sz);
        const r = a -% d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsSub(a, d.imm, r, sz);
    }

    fn executeAndRegImm(self: *MachOState, d: DecodedInsn) void {
        const sz = d.size;
        const a = self.regVal(d.dst_reg, sz);
        const r = a & d.imm;
        self.setReg(d.dst_reg, sz, r);
        self.setFlagsLogic(r, sz);
    }

    fn dispatchMacOSSyscall(self: *MachOState, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64, arg6: u64) void {
        const number = self.regs.rax;
        log.info("syscall: number=0x{x} ({s}) args=({d}, {d}, {d}, {d}, {d}, {d})", .{
            number, macho_runtime.syscallName(number),
            arg1,   arg2,
            arg3,   arg4,
            arg5,   arg6,
        });

        switch (number) {
            @intFromEnum(macho_runtime.Syscall.exit) => {
                const exit_code = arg1;
                log.info("exit({d})", .{exit_code});
                self.termination_reason = @intFromEnum(exit_diagnostics.TerminationReason.exit_syscall);
                self.terminated = true;
                self.exit_code = exit_code;
            },
            @intFromEnum(macho_runtime.Syscall.write) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemoryConst(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd: i32 = if (fd < self.guest_fds.len) self.guest_fds[@as(usize, @intCast(fd))] else -1;
                var written: usize = 0;
                if (host_fd >= 0) {
                    while (written < data.len) {
                        const n = std.c.write(host_fd, data[written..].ptr, data.len - written);
                        if (n <= 0) {
                            self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                            return;
                        }
                        written += @as(usize, @intCast(n));
                    }
                }
                self.regs.rax = @intCast(written);
            },
            @intFromEnum(macho_runtime.Syscall.read) => {
                const fd = arg1;
                const buf = arg2;
                const count = arg3;
                const data = self.guestMemory(buf, count) orelse {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFE;
                    return;
                };
                const host_fd: i32 = if (fd < self.guest_fds.len) self.guest_fds[@as(usize, @intCast(fd))] else -1;
                if (host_fd >= 0) {
                    const n = std.c.read(host_fd, data.ptr, data.len);
                    if (n < 0) {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    }
                    self.regs.rax = @intCast(@as(usize, @intCast(n)));
                } else {
                    self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                }
            },
            @intFromEnum(macho_runtime.Syscall.mmap) => {
                const addr = arg1;
                const length = arg2;
                const prot = arg3;

                const alignment = PAGE_SIZE;
                const aligned_length = ((length + alignment - 1) / alignment) * alignment;

                if (addr != 0) {
                    const off = self.addrToOffset(addr) orelse {
                        self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
                        return;
                    };
                    if (off + aligned_length <= self.mem_size) {
                        if (prot & 0x01 != 0) {
                            @memset(self.mem[off..][0..@as(usize, @intCast(aligned_length))], 0);
                        }
                        self.regs.rax = addr;
                        return;
                    }
                }

                var next_addr = self.mem_base;
                while (next_addr + aligned_length <= self.mem_size) : (next_addr += alignment) {
                    const off = self.addrToOffset(next_addr) orelse break;
                    if (off + aligned_length > self.mem_size) break;
                    var free_range = true;
                    var i: usize = 0;
                    while (i < aligned_length) : (i += alignment) {
                        if (next_addr + i == self.regs.rsp) {
                            free_range = false;
                            break;
                        }
                    }
                    if (!free_range) {
                        next_addr += aligned_length;
                    }
                    if (free_range) {
                        self.regs.rax = next_addr;
                        return;
                    }
                }
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            },
            @intFromEnum(macho_runtime.Syscall.mprotect) => {
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.munmap) => {
                self.regs.rax = 0;
            },
            @intFromEnum(macho_runtime.Syscall.getpid) => {
                self.regs.rax = 42;
            },
            @intFromEnum(macho_runtime.Syscall.issetugid) => {
                self.regs.rax = 0;
            },
            0x2000072 => {
                self.regs.rax = 1;
            },
            else => {
                log.warn("unimplemented syscall: 0x{x}", .{number});
                self.regs.rax = 0xFFFF_FFFF_FFFF_FFFF;
            },
        }
    }
};

fn nextPrime(n: u64) u64 {
    if (n <= 2) return 2;
    var candidate = n;
    if (candidate % 2 == 0) candidate += 1;
    while (true) {
        var is_prime = true;
        var i: u64 = 3;
        while (i <= candidate / i) {
            if (candidate % i == 0) {
                is_prime = false;
                break;
            }
            i += 2;
        }
        if (is_prime) return candidate;
        candidate += 2;
    }
}

fn alignDown(value: u64, alignment: u64) u64 {
    return value & ~(alignment - 1);
}

fn mappedOffset(mem_base: u64, mem_size: u64, mapped_min: u64, address: u64) ?u64 {
    if (address < mapped_min or address < mem_base) return null;
    const offset = address - mem_base;
    return if (offset < mem_size) offset else null;
}

fn parseFopenFlags(mode: []const u8) ?i32 {
    if (mode.len == 0) return null;
    var flags: i32 = 0;
    switch (mode[0]) {
        'r' => flags = 0x0000,
        'w' => flags = 0x0001 | 0x0200 | 0x0400,
        'a' => flags = 0x0001 | 0x0200 | 0x0008,
        else => return null,
    }
    if (std.mem.indexOfScalar(u8, mode, '+') != null) {
        flags &= ~@as(i32, 0x0003);
        flags |= 0x0002;
    }
    return flags;
}

fn alignUp(value: u64, alignment: u64) !u64 {
    const mask = alignment - 1;
    return (try std.math.add(u64, value, mask)) & ~mask;
}

pub const MachORunOptions = struct {
    path: []const u8,
    args: []const []const u8 = &.{},
    trace: bool = false,
};

fn selectedCpuProfile() x64_decoder.capabilities.Profile {
    const raw = std.c.getenv("ROSETTE_X64_CPU_PROFILE") orelse return .xenia;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return x64_decoder.capabilities.parseProfile(value) orelse {
        std.debug.print(
            "macho-processor: unknown ROSETTE_X64_CPU_PROFILE={s}; using xenia\n",
            .{value},
        );
        return .xenia;
    };
}

fn environmentFlag(name: [*:0]const u8) bool {
    const raw = std.c.getenv(name) orelse return false;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "yes");
}

fn environmentUnsigned(name: [*:0]const u8, fallback: u64) u64 {
    const raw = std.c.getenv(name) orelse return fallback;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return std.fmt.parseUnsigned(u64, value, 10) catch fallback;
}

pub fn loadAndRun(io: std.Io, allocator: std.mem.Allocator, options: MachORunOptions) !u64 {
    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, options.path, allocator, .unlimited);
    defer allocator.free(file_data);

    const slice = extractX8664Slice(allocator, file_data) catch |err| {
        std.debug.print("macho-processor: not a valid x86_64 Mach-O binary: {s}\n", .{@errorName(err)});
        return 1;
    };

    var state = try MachOState.init(allocator, slice);
    defer state.deinit();
    state.cpu_profile = selectedCpuProfile();
    state.verbose_trace = options.trace or environmentFlag("ROSETTE_MACHO_VERBOSE_TRACE");
    state.contract_verification = environmentFlag("ROSETTE_CONTRACT_VERIFICATION");
    state.strict_initializers = environmentFlag("ROSETTE_MACHO_STRICT_INITIALIZERS");
    state.strict_imports = environmentFlag("ROSETTE_MACHO_STRICT_IMPORTS");
    state.max_steps = environmentUnsigned("ROSETTE_MACHO_MAX_STEPS", state.max_steps);

    var temp_state = try macho.load(allocator, slice);
    defer temp_state.deinit();

    std.debug.print("macho-processor: {s}\n", .{options.path});
    std.debug.print("  filetype: 0x{x}", .{temp_state.header.filetype});
    switch (temp_state.header.filetype) {
        2 => std.debug.print(" (MH_EXECUTE)\n", .{}),
        6 => std.debug.print(" (MH_DYLIB)\n", .{}),
        8 => std.debug.print(" (MH_BUNDLE)\n", .{}),
        else => std.debug.print("\n", .{}),
    }
    std.debug.print("  cputype:  0x{x}", .{temp_state.header.cputype});
    if (temp_state.header.cputype == macho.CPU_TYPE_X86_64) std.debug.print(" (x86_64)\n", .{}) else std.debug.print("\n", .{});
    std.debug.print("  ncmds:    {d}\n", .{temp_state.header.ncmds});
    std.debug.print("  segments: {d}\n", .{temp_state.segments.len});
    std.debug.print("  entry:    0x{x}\n", .{temp_state.entry_point});
    std.debug.print("  stack:    0x{x}\n", .{temp_state.stack_size});
    std.debug.print("  mem_base: 0x{x}\n", .{state.mem_base});
    std.debug.print("  entry_vaddr: 0x{x}\n", .{state.entry_point_vaddr});
    std.debug.print("  dylibs:    {d}\n", .{state.metadata.dylibs.len});
    std.debug.print("  imports:   {d}\n", .{state.metadata.imports.len});
    std.debug.print("  initializers: {d}\n", .{state.metadata.initializer_count});
    std.debug.print("  strict initializers: {}\n", .{state.strict_initializers});
    std.debug.print("  strict imports: {}\n", .{state.strict_imports});
    std.debug.print("  x64 cpu profile: {s}\n", .{state.cpu_profile.label()});
    std.debug.print(
        "  advertised ISA: SSE4.2={} AVX={} AVX2={} AVX-512F={} XCR0=0x{x}\n",
        .{
            x64_decoder.capabilities.supports(state.cpu_profile, .sse42),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx2),
            x64_decoder.capabilities.supports(state.cpu_profile, .avx512f),
            x64_decoder.capabilities.xcr0(state.cpu_profile),
        },
    );
    if (state.metadata.nearestSymbol(state.entry_point_vaddr)) |entry_symbol| {
        std.debug.print("  entry_symbol: {s}+0x{x}\n", .{ entry_symbol.name, entry_symbol.offset });
    }

    for (temp_state.segments, 0..) |seg, i| {
        const prot_str = switch (seg.initprot) {
            7 => "rwx",
            5 => "r-x",
            3 => "rw-",
            1 => "r--",
            else => "???",
        };
        std.debug.print("    [{d}] {s: <12}  vm=0x{x:0>8}  size=0x{x:0>8}  file=0x{x:0>8}  ({s})\n", .{
            i, seg.name, seg.vmaddr, seg.vmsize, seg.fileoff, prot_str,
        });
    }

    if (temp_state.entry_point == 0) {
        std.debug.print("macho-processor: no entry point found\n", .{});
        return 1;
    }

    state.guest_fds[0] = 0;
    state.guest_fds[1] = 1;
    state.guest_fds[2] = 2;

    state.setupMachOState(options.path, options.args);
    state.launch_options.logConfiguration(state.internal_targets.cvar_add_to_launch_options_count);

    std.debug.print("macho-processor: running {d} pre-main initializer(s)\n", .{state.metadata.initializer_addresses.len});
    const initializers_ok = state.runInitializers();
    state.initializer_resolver.logSummary();
    if (!initializers_ok) {
        state.import_resolver.logSummary();
        state.dynamic_forwarder.logSummary();
        state.fs_forwarder.logSummary();
        state.libcxx_filesystem.logSummary();
        state.libcxx_streams.logSummary();
        state.logging.logSummary();
        state.pthreads.logSummary();
        state.memory_forwarder.logSummary();
        state.launch_options.logSummary();
        state.startup.logSummary();
        state.unwinder.logSummary();
        state.dynamic_casts.logSummary();
        state.diagnostic_text.logSummary();
        state.smart_stubs.logSummary();
        state.logDecodeCacheSummary();
        std.debug.print("macho-processor: initializer phase failed: exit_code={d}\n", .{state.exit_code});
        return state.exit_code;
    }

    std.debug.print("macho-processor: starting execution at 0x{x}, rsp=0x{x}\n", .{ state.regs.rip, state.regs.rsp });

    state.run();

    std.debug.print("macho-processor: execution finished: exit_code={d}, faulted={}, terminated={}\n", .{ state.exit_code, state.faulted, state.terminated });
    state.logDecodeCacheSummary();
    state.import_resolver.logSummary();
    state.dynamic_forwarder.logSummary();
    state.fs_forwarder.logSummary();
    state.libcxx_filesystem.logSummary();
    state.libcxx_streams.logSummary();
    state.logging.logSummary();
    state.pthreads.logSummary();
    state.memory_forwarder.logSummary();
    state.launch_options.logSummary();
    state.startup.logSummary();
    state.smart_stubs.logSummary();
    state.cxx_exceptions.logSummary();
    state.unwinder.logSummary();
    state.dynamic_casts.logSummary();
    state.diagnostic_text.logSummary();
    if (state.guest_log_line_count != 0) {
        std.debug.print(
            "macho-processor: synchronous guest log bridge: mirrored_lines={d}\n",
            .{state.guest_log_line_count},
        );
    }

    if (state.unresolved_import_count != 0) {
        const end = if (state.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else state.import_trace_index;
        for (0..end) |i| {
            const entry = state.import_trace_entries[i];
            if (entry.caller_symbol.len != 0) {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} caller={s}+0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.caller_symbol, entry.caller_offset, entry.synthetic_result },
                );
            } else {
                std.debug.print(
                    "macho-processor: unresolved import #{d}: {s} from {s}; stub=0x{x} return=0x{x} synthesized_rax=0x{x}\n",
                    .{ i, entry.symbol, entry.dylib, entry.stub_address, entry.return_address, entry.synthetic_result },
                );
            }
        }
    }

    if (state.unresolved_import_count != 0 and !state.faulted) {
        std.debug.print(
            "macho-processor: runtime incomplete: {d} unresolved import call(s); guest exit {d} is diagnostic only, returning processor status {d}\n",
            .{ state.unresolved_import_count, state.exit_code, UNSUPPORTED_RUNTIME_EXIT_CODE },
        );
        return UNSUPPORTED_RUNTIME_EXIT_CODE;
    }

    return state.exit_code;
}

fn extractX8664Slice(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    return fat.extractX8664Slice(allocator, data) catch |err| {
        if (err == error.NotMachO) return error.NotMachO;
        if (err == error.NoX86_64Slice) {
            std.debug.print("macho-processor: no x86_64 slice found in fat binary\n", .{});
            return error.NoX86_64Slice;
        }
        return err;
    };
}

fn decodeInsn(bytes: []const u8) DecodedInsn {
    if (bytes.len == 0) return .{};
    var pos: usize = 0;
    var d = DecodedInsn{};
    var rex: u8 = 0;
    var has_66: bool = false;
    var has_f0: bool = false;
    var has_f2: bool = false;
    var has_f3: bool = false;
    var has_0f: bool = false;

    while (pos < bytes.len) {
        switch (bytes[pos]) {
            0x66 => {
                has_66 = true;
                pos += 1;
            },
            0x67 => {
                pos += 1;
            },
            0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65 => {
                // Legacy segment overrides are still accepted in 64-bit mode
                // and are commonly used in compiler-generated long NOPs.
                pos += 1;
            },
            0xF0 => {
                has_f0 = true;
                pos += 1;
            },
            0xF2 => {
                has_f2 = true;
                pos += 1;
            },
            0xF3 => {
                has_f3 = true;
                pos += 1;
            },
            0x40...0x4F => {
                rex = bytes[pos];
                pos += 1;
            },
            else => break,
        }
    }

    if (pos >= bytes.len) return .{};

    const rex_w = (rex & 0x08) != 0;
    const rex_r = (rex & 0x04) != 0;
    const rex_x = (rex & 0x02) != 0;
    const rex_b = (rex & 0x01) != 0;

    const op_size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    _ = op_size;

    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode = bytes[pos];

    if (opcode == 0xC4) {
        return decodeVex3(bytes, pos);
    }
    if (opcode == 0xC5) {
        return decodeVex2(bytes, pos);
    }

    if (opcode == 0x0F) {
        pos += 1;
        if (pos >= bytes.len) return .{};
        has_0f = true;
        return decodeTwoByte(bytes, &pos, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, rex);
    }

    if (opcode == 0x90) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos + 1));
        return d;
    }

    if (opcode == 0xF5 or opcode == 0xF8 or opcode == 0xF9) {
        d.op = switch (opcode) {
            0xF5 => .cmc,
            0xF8 => .clc,
            0xF9 => .stc,
            else => unreachable,
        };
        d.len = @intCast(pos + 1);
        return d;
    }

    switch (opcode) {
        0x50...0x57 => {
            d.op = .push_reg;
            const reg_num: u8 = opcode - 0x50;
            d.dst_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x58...0x5F => {
            d.op = .pop_reg;
            const reg_num: u8 = opcode - 0x58;
            d.dst_reg = mapReg(reg_num, rex_b);
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x63 => {
            if (!rex_w or pos + 1 >= bytes.len) return .{};
            var movsxd = DecodedInsn{ .size = .bits64 };
            var modrm_pos = pos + 1;
            const is_mem = bytes[modrm_pos] < 0xC0;
            const rm = readModRM(&movsxd, bytes, &modrm_pos, rex_r, rex_x, rex_b, .bits32);
            movsxd.dst_reg = rm.reg;
            if (is_mem) {
                movsxd.op = .movsxd_reg64_mem32;
                movsxd.addr = rm.addr;
            } else {
                movsxd.op = .movsxd_reg64_reg32;
                movsxd.src_reg = @enumFromInt(rm.addr);
            }
            movsxd.len = @intCast(modrm_pos);
            return movsxd;
        },

        0x68, 0x6A => {
            d.op = .push_imm;
            if (opcode == 0x68) {
                if (pos + 5 > bytes.len) return .{};
                d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.len = 6;
            } else {
                if (pos + 2 > bytes.len) return .{};
                d.imm = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
                d.len = 2;
            }
        },

        0xAC, 0xAD => {
            d.op = .lods;
            d.size = if (opcode == 0xAC) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x69, 0x6B => {
            return decodeImulImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x70...0x7F => {
            d.op = .jcc_rel8;
            d.cond = mapJccCond8(opcode);
            if (pos + 2 > bytes.len) return .{};
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0x84, 0x85 => {
            return decodeTestRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x86, 0x87 => {
            return decodeXchgRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x88, 0x89, 0x8A, 0x8B => {
            return decodeMovRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x8D => {
            return decodeLea(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x8F => {
            return decodePopRm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66);
        },

        0x00...0x03 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .add);
        },
        0x08...0x0B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"or");
        },
        0x20...0x23 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .@"and");
        },
        0x28...0x2B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .sub);
        },
        0x30...0x33 => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .xor);
        },
        0x38...0x3B => {
            return decodeArithRmReg(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode, .cmp);
        },

        0x80...0x83 => {
            return decodeGroup1Imm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xC0, 0xC1, 0xD0, 0xD1, 0xD2, 0xD3 => {
            return decodeGroup2Shift(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xF6, 0xF7 => {
            return decodeGroup3(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xB0...0xB7 => {
            d.op = .mov_reg_imm;
            d.dst_reg = mapReg(opcode - 0xB0, rex_b);
            d.size = .bits8;
            if (pos + 2 > bytes.len) return .{};
            d.imm = bytes[pos + 1];
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xC2, 0xC3 => {
            d.op = .ret;
            if (opcode == 0xC2) {
                if (pos + 3 > bytes.len) return .{};
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                d.len = 3;
            } else {
                d.imm = 0;
                d.len = @as(u8, @intCast(pos + 1));
            }
        },

        0xC6, 0xC7 => {
            return decodeMovMemImm(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0xCC => {
            d.op = .hlt;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0xE8 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .call_rel32;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },

        0xE9 => {
            if (pos + 5 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos + 1 ..][0..4], .little))));
            d.rip_relative = true;
            d.len = 5;
        },
        0xEB => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .jmp_rel8;
            d.addr = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos + 1])))));
            d.rip_relative = true;
            d.len = 2;
        },

        0xFE, 0xFF => {
            return decodeGroup4_5(bytes, pos, rex_r, rex_x, rex_b, rex_w, has_66, opcode);
        },

        0x98 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x99 => {
            if (rex_w) {
                d.op = .cqo;
            } else if (has_66) {
                d.op = .cwd;
            } else {
                d.op = .cdq;
            }
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9B => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x05 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .add_accum_imm),
        0x0D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .or_accum_imm),
        0x15 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .adc_accum_imm),
        0x1D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .sbb_accum_imm),
        0x25 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .and_accum_imm),
        0x2D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .sub_accum_imm),
        0x35 => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .xor_accum_imm),
        0x3D => return decodeAccumulatorImmediate(bytes, pos, rex_w, has_66, .cmp_accum_imm),

        0x8C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 2));
        },

        0xA8 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .test_reg8_imm8;
            d.size = .bits8;
            d.dst_reg = .al_ax_eax_rax;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0xA9 => {
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            const imm_len: usize = if (sz == .bits16) 2 else 4;
            if (pos + 1 + imm_len > bytes.len) return .{};
            d.op = switch (sz) {
                .bits16 => .test_reg16_imm16,
                .bits32 => .test_reg32_imm32,
                .bits64 => .test_reg64_imm32,
                .bits8 => unreachable,
            };
            d.size = sz;
            d.dst_reg = .al_ax_eax_rax;
            if (sz == .bits16) {
                d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
            } else {
                const imm32 = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                d.imm = if (sz == .bits64)
                    @bitCast(@as(i64, @as(i32, @bitCast(imm32))))
                else
                    imm32;
            }
            d.len = @intCast(pos + 1 + imm_len);
        },

        0xB8...0xBF => {
            d.op = .mov_reg_imm;
            d.dst_reg = mapReg(opcode - 0xB8, rex_b);
            const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
            d.size = sz;
            switch (sz) {
                .bits16 => {
                    if (pos + 3 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u16, bytes[pos + 1 ..][0..2], .little);
                    d.len = @as(u8, @intCast(pos + 3));
                },
                .bits32 => {
                    if (pos + 5 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u32, bytes[pos + 1 ..][0..4], .little);
                    d.len = @as(u8, @intCast(pos + 5));
                },
                .bits64 => {
                    if (pos + 9 > bytes.len) return .{};
                    d.imm = std.mem.readInt(u64, bytes[pos + 1 ..][0..8], .little);
                    d.len = @as(u8, @intCast(pos + 9));
                },
                .bits8 => unreachable,
            }
        },

        0x0C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .or_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x14 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .adc_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x1C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sbb_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x24 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .and_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x2C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .sub_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x34 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .xor_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x3C => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .cmp_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },
        0x04 => {
            if (pos + 2 > bytes.len) return .{};
            d.op = .add_reg8_imm8;
            d.dst_reg = mapReg(0, rex_b);
            d.size = .bits8;
            d.imm = bytes[pos + 1];
            d.len = @intCast(pos + 2);
        },

        0x40...0x47 => {
            if (opcode == 0x40) {
                d.op = .nop;
            } else {
                d.op = .inc_reg64;
                const reg_num: u8 = opcode - 0x40;
                d.dst_reg = mapReg(reg_num, false);
            }
            d.len = @as(u8, @intCast(pos + 1));
        },

        0xC9 => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x6C, 0x6D, 0x6E, 0x6F => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        0x9C => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9D => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },
        0x9E => {
            d.op = .nop;
            d.len = @as(u8, @intCast(pos + 1));
        },

        else => {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos + 1));
        },
    }

    return d;
}

fn decodeVex2(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 3 > bytes.len) return .{};

    const vex = bytes[start_pos + 1];
    const opcode = bytes[start_pos + 2];
    const rex_r = (vex & 0x80) == 0;
    const vector_256 = (vex & 0x04) != 0;
    const prefix = vex & 0x03;

    if (opcode == 0x77 and (vex & 0x78) == 0x78 and !vector_256 and prefix == 0) {
        return .{ .op = .vzeroupper, .len = @intCast(start_pos + 3) };
    }
    if (start_pos + 3 >= bytes.len) return .{};

    if (opcode == 0x6E and (vex & 0x78) == 0x78 and !vector_256 and prefix == 1) {
        var decoded = DecodedInsn{ .size = .bits32 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits32);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.op = .vmovd_xmm_mem32;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vmovd_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x76 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 3;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, false, false, .bits64);
        decoded.op = .vpcmpeqd;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode == 0x58 or opcode == 0x59 or opcode == 0x5C or opcode == 0x5E) {
        if (vector_256 and (prefix == 2 or prefix == 3)) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var arithmetic_pos = start_pos + 3;
        const is_mem = bytes[arithmetic_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &arithmetic_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x58 => switch (prefix) {
                0 => .vaddps,
                1 => .vaddpd,
                2 => .vaddss,
                3 => .vaddsd,
                else => unreachable,
            },
            0x59 => switch (prefix) {
                0 => .vmulps,
                1 => .vmulpd,
                2 => .vmulss,
                3 => .vmulsd,
                else => unreachable,
            },
            0x5C => switch (prefix) {
                0 => .vsubps,
                1 => .vsubpd,
                2 => .vsubss,
                3 => .vsubsd,
                else => unreachable,
            },
            0x5E => switch (prefix) {
                0 => .vdivps,
                1 => .vdivpd,
                2 => .vdivss,
                3 => .vdivsd,
                else => unreachable,
            },
            else => unreachable,
        };
        decoded.len = @intCast(arithmetic_pos);
        return decoded;
    }

    if (opcode >= 0x54 and opcode <= 0x57 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var bitwise_pos = start_pos + 3;
        const is_mem = bytes[bitwise_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &bitwise_pos, rex_r, false, false, .bits64);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = switch (opcode) {
            0x54 => if (prefix == 0) .vandps else .vandpd,
            0x55 => if (prefix == 0) .vandnps else .vandnpd,
            0x56 => if (prefix == 0) .vorps else .vorpd,
            0x57 => if (prefix == 0) .vxorps else .vxorpd,
            else => unreachable,
        };
        decoded.len = @intCast(bitwise_pos);
        return decoded;
    }

    if ((opcode == 0x2E or opcode == 0x2F) and (vex & 0x78) == 0x78 and !vector_256 and (prefix == 0 or prefix == 1)) {
        var decoded = DecodedInsn{};
        var compare_pos = start_pos + 3;
        const is_mem = bytes[compare_pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &compare_pos, rex_r, false, false, .bits64);
        decoded.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.op = if (prefix == 0) .vucomiss else .vucomisd;
        decoded.len = @intCast(compare_pos);
        return decoded;
    }

    if ((vex & 0x78) != 0x78) return .{};

    var d = DecodedInsn{};
    var pos = start_pos + 3;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, false, false, .bits64);

    const is_load = switch (opcode) {
        0x6F, 0x10, 0x28 => true,
        0x7F, 0x11, 0x29 => false,
        else => return .{},
    };

    const family: enum { dqu, dqa, ups, aps, upd, apd, ss, sd } = switch (opcode) {
        0x6F, 0x7F => switch (prefix) {
            1 => .dqa,
            2 => .dqu,
            else => return .{},
        },
        0x10, 0x11 => switch (prefix) {
            0 => .ups,
            1 => .upd,
            2 => .ss,
            3 => .sd,
            else => unreachable,
        },
        0x28, 0x29 => switch (prefix) {
            0 => .aps,
            1 => .apd,
            else => return .{},
        },
        else => unreachable,
    };

    if ((family == .ss or family == .sd) and !is_mem) return .{};
    if ((family == .ss or family == .sd) and vector_256) return .{};

    if (is_load) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_mem,
                .dqa => .vmovdqa_ymm_mem,
                .ups => .vmovups_ymm_mem,
                .aps => .vmovaps_ymm_mem,
                .upd => .vmovupd_ymm_mem,
                .apd => .vmovapd_ymm_mem,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_mem,
                .dqa => .vmovdqa_xmm_mem,
                .ups => .vmovups_xmm_mem,
                .aps => .vmovaps_xmm_mem,
                .upd => .vmovupd_xmm_mem,
                .apd => .vmovapd_xmm_mem,
                .ss => .vmovss_xmm_mem,
                .sd => .vmovsd_xmm_mem,
            };
        } else {
            d.xmm_src = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.addr = rm.addr;
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_mem_ymm,
                .dqa => .vmovdqa_mem_ymm,
                .ups => .vmovups_mem_ymm,
                .aps => .vmovaps_mem_ymm,
                .upd => .vmovupd_mem_ymm,
                .apd => .vmovapd_mem_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_mem_xmm,
                .dqa => .vmovdqa_mem_xmm,
                .ups => .vmovups_mem_xmm,
                .aps => .vmovaps_mem_xmm,
                .upd => .vmovupd_mem_xmm,
                .apd => .vmovapd_mem_xmm,
                .ss => .vmovss_mem_xmm,
                .sd => .vmovsd_mem_xmm,
            };
        } else {
            d.xmm_dst = @intCast(rm.addr);
            d.op = if (vector_256) switch (family) {
                .dqu => .vmovdqu_ymm_ymm,
                .dqa => .vmovdqa_ymm_ymm,
                .ups => .vmovups_ymm_ymm,
                .aps => .vmovaps_ymm_ymm,
                .upd => .vmovupd_ymm_ymm,
                .apd => .vmovapd_ymm_ymm,
                .ss, .sd => unreachable,
            } else switch (family) {
                .dqu => .vmovdqu_xmm_xmm,
                .dqa => .vmovdqa_xmm_xmm,
                .ups => .vmovups_xmm_xmm,
                .aps => .vmovaps_xmm_xmm,
                .upd => .vmovupd_xmm_xmm,
                .apd => .vmovapd_xmm_xmm,
                .ss, .sd => unreachable,
            };
        }
    }

    d.len = @intCast(pos);
    return d;
}

const VexArithmetic = enum { add, multiply, subtract, divide };
const VexBitwise = enum { @"and", and_not, @"or", xor };
fn shuffleBytes(source: [16]u8, mask: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (mask, 0..) |selector, index| {
        if (selector & 0x80 == 0) result[index] = source[selector & 0x0F];
    }
    return result;
}

fn compareEqualDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const left = std.mem.readInt(u32, lhs[offset..][0..4], .little);
        const right = std.mem.readInt(u32, rhs[offset..][0..4], .little);
        std.mem.writeInt(u32, result[offset..][0..4], if (left == right) std.math.maxInt(u32) else 0, .little);
    }
    return result;
}

fn vexArithmeticForOp(op: Op) VexArithmetic {
    return switch (op) {
        .vaddss, .vaddsd, .vaddps, .vaddpd => .add,
        .vmulss, .vmulsd, .vmulps, .vmulpd => .multiply,
        .vsubss, .vsubsd, .vsubps, .vsubpd => .subtract,
        .vdivss, .vdivsd, .vdivps, .vdivpd => .divide,
        else => unreachable,
    };
}

fn applyVexArithmetic(comptime Float: type, lhs: Float, rhs: Float, operation: VexArithmetic) Float {
    return switch (operation) {
        .add => lhs + rhs,
        .multiply => lhs * rhs,
        .subtract => lhs - rhs,
        .divide => lhs / rhs,
    };
}

fn vexBitwiseForOp(op: Op) VexBitwise {
    return switch (op) {
        .vandps, .vandpd => .@"and",
        .vandnps, .vandnpd => .and_not,
        .vorps, .vorpd => .@"or",
        .vxorps, .vxorpd => .xor,
        else => unreachable,
    };
}

fn applyVexBitwise(lhs: [16]u8, rhs: [16]u8, operation: VexBitwise) [16]u8 {
    var result: [16]u8 = undefined;
    for (&result, lhs, rhs) |*destination, left, right| {
        destination.* = switch (operation) {
            .@"and" => left & right,
            .and_not => ~left & right,
            .@"or" => left | right,
            .xor => left ^ right,
        };
    }
    return result;
}

fn applyVexPackedF32(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const lhs_value: f32 = @bitCast(std.mem.readInt(u32, lhs[offset..][0..4], .little));
        const rhs_value: f32 = @bitCast(std.mem.readInt(u32, rhs[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(applyVexArithmetic(f32, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

fn applyVexPackedF64(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const lhs_value: f64 = @bitCast(std.mem.readInt(u64, lhs[offset..][0..8], .little));
        const rhs_value: f64 = @bitCast(std.mem.readInt(u64, rhs[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(applyVexArithmetic(f64, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

fn roundVexFloat(comptime Float: type, value: Float, immediate: u8) Float {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;
    const mode: u2 = if (immediate & 0x04 != 0) 0 else @truncate(immediate);
    return switch (mode) {
        0 => roundNearestEven(Float, value),
        1 => @floor(value),
        2 => @ceil(value),
        3 => @trunc(value),
    };
}

fn roundNearestEven(comptime Float: type, value: Float) Float {
    const lower = @floor(value);
    const fraction = value - lower;
    const half: Float = 0.5;
    if (fraction < half) return lower;
    if (fraction > half) return lower + 1.0;
    return if (@mod(lower, 2.0) == 0.0) lower else lower + 1.0;
}

fn roundVexPackedF32(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const value: f32 = @bitCast(std.mem.readInt(u32, source[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(roundVexFloat(f32, value, immediate)), .little);
    }
    return result;
}

fn roundVexPackedF64(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const value: f64 = @bitCast(std.mem.readInt(u64, source[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(roundVexFloat(f64, value, immediate)), .little);
    }
    return result;
}

fn convertVexFloatToSigned(comptime Float: type, value: Float, size: Size, truncate: bool) u64 {
    const rounded = if (truncate) @trunc(value) else roundNearestEven(Float, value);
    if (std.math.isNan(rounded)) return integerIndefinite(size);

    return switch (size) {
        .bits32 => blk: {
            const minimum: Float = -2147483648.0;
            const maximum_exclusive: Float = 2147483648.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i32 = @intFromFloat(rounded);
            break :blk @as(u32, @bitCast(signed));
        },
        .bits64 => blk: {
            const minimum: Float = -9223372036854775808.0;
            const maximum_exclusive: Float = 9223372036854775808.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i64 = @intFromFloat(rounded);
            break :blk @bitCast(signed);
        },
        else => unreachable,
    };
}

fn integerIndefinite(size: Size) u64 {
    return if (size == .bits64) @as(u64, 1) << 63 else @as(u64, 1) << 31;
}

fn decodeVex3(bytes: []const u8, start_pos: usize) DecodedInsn {
    if (start_pos + 5 > bytes.len) return .{};
    const vex_map = bytes[start_pos + 1];
    const vex_control = bytes[start_pos + 2];
    const opcode = bytes[start_pos + 3];
    const opcode_map = vex_map & 0x1F;
    const rex_r = (vex_map & 0x80) == 0;
    const rex_x = (vex_map & 0x40) == 0;
    const rex_b = (vex_map & 0x20) == 0;
    const rex_w = (vex_control & 0x80) != 0;
    const vector_256 = (vex_control & 0x04) != 0;
    const prefix = vex_control & 0x03;

    if (opcode_map == 1 and opcode == 0x76 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpcmpeqd;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        decoded.is_reg_form = !is_mem;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x6E or opcode == 0x7E)) {
        if (!rex_w or vector_256 or prefix != 1 or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = .bits64 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (opcode == 0x6E) {
            decoded.xmm_dst = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = .vmovq_xmm_mem64;
                decoded.addr = rm.addr;
            } else {
                decoded.op = .vmovq_xmm_reg64;
                decoded.src_reg = @enumFromInt(rm.addr);
            }
        } else {
            decoded.xmm_src = @intFromEnum(rm.reg);
            if (is_mem) {
                decoded.op = .vmovq_mem64_xmm;
                decoded.addr = rm.addr;
            } else {
                decoded.op = .vmovq_reg64_xmm;
                decoded.dst_reg = @enumFromInt(rm.addr);
            }
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and opcode == 0x2A) {
        if (vector_256 or (prefix != 2 and prefix != 3)) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @as(u8, @truncate((~vex_control >> 3) & 0x0F));
        if (is_mem) {
            decoded.addr = rm.addr;
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_mem else .vcvtsi2sd_xmm_mem;
        } else {
            decoded.src_reg = @enumFromInt(rm.addr);
            decoded.op = if (prefix == 2) .vcvtsi2ss_xmm_reg else .vcvtsi2sd_xmm_reg;
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 1 and (opcode == 0x2C or opcode == 0x2D)) {
        if (vector_256 or (prefix != 2 and prefix != 3) or (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .size = if (rex_w) .bits64 else .bits32 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, decoded.size);
        decoded.dst_reg = rm.reg;
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src = @intCast(rm.addr);
        }
        decoded.op = if (opcode == 0x2C)
            if (prefix == 2) .vcvttss2si else .vcvttsd2si
        else if (prefix == 2)
            .vcvtss2si
        else
            .vcvtsd2si;
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 2 and opcode == 0x00 and prefix == 1) {
        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        decoded.op = .vpshufb;
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode >= 0x08 and opcode <= 0x0B and prefix == 1) {
        const is_scalar = opcode == 0x0A or opcode == 0x0B;
        if (is_scalar and vector_256) return .{};
        if (!is_scalar and (vex_control & 0x78) != 0x78) return .{};

        var decoded = DecodedInsn{ .vector_256 = vector_256 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.addr = rm.addr;
        } else {
            decoded.xmm_src2 = @intCast(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.op = switch (opcode) {
            0x08 => .vroundps,
            0x09 => .vroundpd,
            0x0A => .vroundss,
            0x0B => .vroundsd,
            else => unreachable,
        };
        decoded.len = @intCast(pos);
        return decoded;
    }

    if (opcode_map == 3 and opcode == 0x20 and prefix == 1 and !vector_256) {
        var decoded = DecodedInsn{ .size = .bits8 };
        var pos = start_pos + 4;
        const is_mem = bytes[pos] < 0xC0;
        const rm = readModRM(&decoded, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        decoded.xmm_dst = @intFromEnum(rm.reg);
        decoded.xmm_src = @truncate((~vex_control >> 3) & 0x0F);
        if (is_mem) {
            decoded.op = .vpinsrb_xmm_xmm_mem8;
            decoded.addr = rm.addr;
        } else {
            decoded.op = .vpinsrb_xmm_xmm_reg32;
            decoded.src_reg = @enumFromInt(rm.addr);
        }
        decoded.imm = bytes[pos];
        pos += 1;
        decoded.len = @intCast(pos);
        return decoded;
    }

    return .{};
}

fn decodeAccumulatorImmediate(bytes: []const u8, opcode_pos: usize, rex_w: bool, has_66: bool, op: Op) DecodedInsn {
    const size: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const immediate_size: usize = if (size == .bits16) 2 else 4;
    if (opcode_pos + 1 + immediate_size > bytes.len) return .{};

    var decoded = DecodedInsn{
        .op = op,
        .size = size,
        .dst_reg = .al_ax_eax_rax,
        .len = @intCast(opcode_pos + 1 + immediate_size),
    };
    if (size == .bits16) {
        decoded.imm = std.mem.readInt(u16, bytes[opcode_pos + 1 ..][0..2], .little);
    } else {
        const immediate = std.mem.readInt(u32, bytes[opcode_pos + 1 ..][0..4], .little);
        decoded.imm = if (size == .bits64)
            @bitCast(@as(i64, @as(i32, @bitCast(immediate))))
        else
            immediate;
    }
    return decoded;
}

fn decodeTwoByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, _: u8) DecodedInsn {
    var d = DecodedInsn{};
    d.size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const opcode2 = bytes[pos.*];
    pos.* += 1;

    if (opcode2 == 0x05) {
        d.op = .syscall;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x1F) {
        if (pos.* >= bytes.len) return .{};
        _ = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits32);
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x40 and opcode2 <= 0x4F) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        d.cond = @enumFromInt(@as(u4, @truncate(opcode2 & 0x0F)));
        if (d.is_reg_form) {
            d.op = .cmovcc_reg_reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.op = .cmovcc_reg_mem;
            d.addr = rm.addr;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 >= 0x80 and opcode2 <= 0x8F) {
        d.op = .jcc_rel32;
        d.cond = mapJccCond32(opcode2);
        if (pos.* + 4 > bytes.len) return .{};
        d.addr = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
        d.rip_relative = true;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 >= 0x90 and opcode2 <= 0x9F) {
        return decodeSetcc(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xA2) {
        d.op = .cpuid;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x01 and pos.* < bytes.len and bytes[pos.*] == 0xD0) {
        pos.* += 1;
        d.op = .xgetbv;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0xAF) {
        return decodeImulTwoOp(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB0 or opcode2 == 0xB1) {
        return decodeCmpxchg(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xB6 or opcode2 == 0xB7) {
        return decodeMovzx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xBC or opcode2 == 0xBD) {
        if (pos.* >= bytes.len) return .{};
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, d.size);
        d.dst_reg = rm.reg;
        if (d.is_reg_form) {
            d.src_reg = @enumFromInt(rm.addr);
            d.op = if (has_f3)
                if (opcode2 == 0xBC) .tzcnt_reg_reg else .lzcnt_reg_reg
            else if (opcode2 == 0xBC)
                .bsf_reg_reg
            else
                .bsr_reg_reg;
        } else {
            d.addr = rm.addr;
            d.op = if (has_f3)
                if (opcode2 == 0xBC) .tzcnt_reg_mem else .lzcnt_reg_mem
            else if (opcode2 == 0xBC)
                .bsf_reg_mem
            else
                .bsr_reg_mem;
        }
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0xBE or opcode2 == 0xBF) {
        return decodeMovsx(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0xC1) {
        return decodeXadd(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 >= 0xC8 and opcode2 <= 0xCF) {
        if (has_66) return .{};
        d.op = .bswap_reg;
        d.size = if (rex_w) .bits64 else .bits32;
        d.dst_reg = mapReg(opcode2 - 0xC8, rex_b);
        d.len = @intCast(pos.*);
        return d;
    }

    if (opcode2 == 0x10 or opcode2 == 0x11) {
        return decodeMovupsMovss(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, opcode2);
    }

    if (opcode2 == 0x28 or opcode2 == 0x29) {
        return decodeMovaps(bytes, pos.* - 1, rex_r, rex_x, rex_b, rex_w, has_66, opcode2);
    }

    if (opcode2 == 0x2E or opcode2 == 0x2F) {
        d.op = .nop;
        const extra = if (pos.* + 1 <= bytes.len and hasModRM(bytes[pos.*])) @as(u8, 1) else @as(u8, 0);
        d.len = @as(u8, @intCast(pos.* + extra));
        return d;
    }

    if (opcode2 == 0x38) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x38);
    }

    if (opcode2 == 0x3A) {
        return decodeThreeByte(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, has_f2, has_f3, 0x3A);
    }

    if (opcode2 == 0x40 or opcode2 == 0x41) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x50 or opcode2 == 0x51) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }

    if (opcode2 == 0x54) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x55) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"and");
    }

    if (opcode2 == 0x56) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .@"or");
    }

    if (opcode2 == 0x57) {
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, has_66, opcode2, .xor);
    }

    if (opcode2 == 0x58 or opcode2 == 0x59 or opcode2 == 0x5C or opcode2 == 0x5E or opcode2 == 0x5F) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0x70) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 3));
        return d;
    }

    if (opcode2 == 0xD1 or opcode2 == 0xD2 or opcode2 == 0xD3) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xE6) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xEF) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xF1 or opcode2 == 0xF2 or opcode2 == 0xF3 or opcode2 == 0xF4 or opcode2 == 0xF5) {
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 2));
        return d;
    }

    if (opcode2 == 0xAE) {
        if (pos.* < bytes.len) {
            const modrm = bytes[pos.*];
            const reg = (modrm >> 3) & 7;
            if (reg == 5 or reg == 6 or reg == 7) {
                d.op = .nop;
                d.len = @as(u8, @intCast(pos.* + 1));
                return d;
            }
        }
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.* + 1));
        return d;
    }

    return .{};
}

fn decodeThreeByte(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode: u8) DecodedInsn {
    _ = has_66;
    _ = has_f2;
    _ = has_f3;
    _ = opcode;
    if (pos.* >= bytes.len) return .{};
    const opcode3 = bytes[pos.*];
    if (opcode3 == 0xF5 or opcode3 == 0xF7 or opcode3 == 0xFA or opcode3 == 0xFB or opcode3 == 0xFC) {
        pos.* += 1;
        return decodeSseBytes(bytes, &pos.*, rex_r, rex_x, rex_b, rex_w, false, opcode3, .nop);
    }
    var d = DecodedInsn{};
    d.op = .nop;
    d.len = @as(u8, @intCast(pos.* + 1));
    return d;
}

fn decodeSseBytes(bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, sse_op: anytype) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    _ = opcode;
    var d = DecodedInsn{};
    if (pos.* >= bytes.len) return .{};
    const modrm = bytes[pos.*];
    const is_reg = modrm >= 0xC0;
    if (is_reg) {
        const rm = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.xmm_dst = @intFromEnum(rm.reg);
        d.xmm_src = @intFromEnum(@as(RegId, @enumFromInt(@as(u8, @intCast(rm.addr)))));
        if (comptime std.mem.eql(u8, @tagName(sse_op), "xor")) {
            d.op = .xorps_xmm_xmm;
        } else {
            d.op = .nop;
        }
        d.len = @as(u8, @intCast(pos.*));
        return d;
    } else {
        _ = readModRM(&d, bytes, pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .nop;
        d.len = @as(u8, @intCast(pos.*));
        return d;
    }
}

fn hasModRM(byte: u8) bool {
    _ = byte;
    return true;
}

fn mapReg(reg_num: u8, rex_b: bool) RegId {
    const r = reg_num + @as(u8, if (rex_b) 8 else 0);
    return @enumFromInt(r);
}

fn mapJccCond8(opcode: u8) Cond {
    const conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };
    return conditions[opcode & 0x0F];
}

fn mapJccCond32(opcode: u8) Cond {
    const conditions: [12]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np,
    };
    const idx = opcode & 0x0F;
    if (idx < 12) return conditions[idx];
    if (idx == 12) return .l;
    if (idx == 13) return .ge;
    if (idx == 14) return .le;
    return .g;
}

fn readModRM(d: *DecodedInsn, bytes: []const u8, pos: *usize, rex_r: bool, rex_x: bool, rex_b: bool, _: Size) struct { reg: RegId, addr: u64 } {
    const modrm = bytes[pos.*];
    pos.* += 1;
    const mod = (modrm >> 6) & 3;
    const reg_num = (modrm >> 3) & 7;
    const rm_num = modrm & 7;

    const reg = mapReg(reg_num, rex_r);

    d.sib_has_base = false;
    d.sib_has_index = false;
    d.rip_relative = false;
    d.is_reg_form = false;

    if (mod == 3) {
        d.is_reg_form = true;
        return .{ .reg = reg, .addr = @as(u64, @intFromEnum(mapReg(rm_num, rex_b))) };
    }

    var disp: u64 = 0;

    if (rm_num == 4) {
        const sib = bytes[pos.*];
        pos.* += 1;
        const scale = (sib >> 6) & 3;
        const index_num = (sib >> 3) & 7;
        const base_num = sib & 7;

        if (index_num != 4) {
            d.sib_has_index = true;
            d.sib_index_reg = mapReg(index_num, rex_x);
            d.sib_scale = @as(u2, @intCast(scale));
        }

        if (mod == 0 and base_num == 5) {
            d.rip_relative = true;
        } else {
            d.sib_has_base = true;
            d.sib_base_reg = mapReg(base_num, rex_b);
        }

        if (mod == 0 and base_num == 5) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        } else if (mod == 1) {
            disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
            pos.* += 1;
        } else if (mod == 2) {
            if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
            disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
            pos.* += 4;
        }
        return .{ .reg = reg, .addr = disp };
    }

    if (mod == 0 and rm_num == 5) {
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        d.rip_relative = true;
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else if (mod == 1) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        disp = @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos.*])))));
        pos.* += 1;
    } else if (mod == 2) {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
        if (pos.* + 4 > bytes.len) return .{ .reg = reg, .addr = 0 };
        disp = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, bytes[pos.*..][0..4], .little))));
        pos.* += 4;
    } else {
        d.sib_has_base = true;
        d.sib_base_reg = mapReg(rm_num, rex_b);
    }

    return .{ .reg = reg, .addr = disp };
}

fn decodeArithRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8, arith_type: enum { add, @"or", adc, sbb, @"and", sub, xor, cmp }) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    const is_byte = (opcode & 0x01) == 0;
    const sz: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
    const is_reg_reg = bytes[start_pos + 1] >= 0xC0;
    const is_mem_to_reg = (opcode & 0x02) != 0;

    const reg_mem_ops: [8]Op = .{
        .add_reg8_mem8, .or_reg8_mem8,  .adc_reg8_mem8, .sbb_reg8_mem8,
        .and_reg8_mem8, .sub_reg8_mem8, .xor_reg8_mem8, .cmp_reg8_mem8,
    };
    const mem_reg_ops: [8]Op = .{
        .add_mem8_reg8, .or_mem8_reg8,  .invalid,       .invalid,
        .and_mem8_reg8, .sub_mem8_reg8, .xor_mem8_reg8, .cmp_mem8_reg8,
    };
    const reg_reg_ops: [8]Op = .{
        .add_reg8_reg8, .or_reg8_reg8,  .invalid,       .invalid,
        .and_reg8_reg8, .sub_reg8_reg8, .xor_reg8_reg8, .cmp_reg8_reg8,
    };

    const base_op = if (is_reg_reg)
        reg_reg_ops[@intFromEnum(arith_type)]
    else if (is_mem_to_reg)
        reg_mem_ops[@intFromEnum(arith_type)]
    else
        mem_reg_ops[@intFromEnum(arith_type)];
    const off = @intFromEnum(sz) - @intFromEnum(Size.bits8);
    d.op = if (base_op == .invalid)
        .invalid
    else
        @enumFromInt(@intFromEnum(base_op) + off);

    if (is_reg_reg) {
        if (is_mem_to_reg) {
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        }
        d.is_reg_form = true;
    } else if (is_mem_to_reg) {
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.src_reg = rm.reg;
        d.addr = rm.addr;
    }
    d.size = sz;
    d.len = @as(u8, @intCast(pos));

    return d;
}

fn decodeMovRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;

    _ = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x88 or opcode == 0x8A) .bits8 else .bits32;

    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];

    const to_reg = (opcode & 0x02) != 0;
    const byte_op = opcode == 0x88 or opcode == 0x8A;

    const actual_sz: Size = if (byte_op) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, actual_sz);
    const is_reg = modrm >= 0xC0;

    if (to_reg) {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = rm.reg;
            d.src_reg = @enumFromInt(rm.addr);
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_mem8,
                .bits16 => .mov_reg16_mem16,
                .bits32 => .mov_reg32_mem32,
                .bits64 => .mov_reg64_mem64,
            };
            d.dst_reg = rm.reg;
            d.addr = rm.addr;
        }
    } else {
        if (is_reg) {
            d.op = switch (actual_sz) {
                .bits8 => .mov_reg8_reg8,
                .bits16 => .mov_reg16_reg16,
                .bits32 => .mov_reg32_reg32,
                .bits64 => .mov_reg64_reg64,
            };
            d.dst_reg = @enumFromInt(rm.addr);
            d.src_reg = rm.reg;
        } else {
            d.op = switch (actual_sz) {
                .bits8 => .mov_mem8_reg8,
                .bits16 => .mov_mem16_reg16,
                .bits32 => .mov_mem32_reg32,
                .bits64 => .mov_mem64_reg64,
            };
            d.addr = rm.addr;
            d.src_reg = rm.reg;
        }
    }

    d.size = actual_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeLea(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (modrm < 0xC0) {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        d.op = .lea_reg_mem;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
        d.size = sz;
        d.len = @as(u8, @intCast(pos));
        return d;
    }
    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodePopRm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits64;
    _ = sz;
    if (modrm >= 0xC0) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);
        d.op = .pop_reg;
        d.dst_reg = @enumFromInt(rm.addr);
    } else {
        d.op = .pop_mem64;
        d.addr = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64).addr;
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup1Imm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x80) .bits8 else .bits32;

    const is_byte_imm = opcode == 0x80 or opcode == 0x83;
    const imm_size: u8 = if (is_byte_imm) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (is_byte_imm)
        if (opcode == 0x83) @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos]))))) else bytes[pos]
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else if (sz == .bits64)
        @as(u64, @bitCast(@as(i64, @as(i32, @bitCast(std.mem.readInt(u32, bytes[pos..][0..4], .little))))))
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    const base_sz = if (sz == .bits8) Size.bits8 else if (sz == .bits16) Size.bits16 else if (sz == .bits32) Size.bits32 else Size.bits64;

    const group_ops: [8]Op = .{
        .add_reg8_imm8, .or_reg8_imm8,  .adc_reg8_imm8, .sbb_reg8_imm8,
        .and_reg8_imm8, .sub_reg8_imm8, .xor_reg8_imm8, .cmp_reg8_imm8,
    };

    if (is_mem) {
        if (group_op == 1) {
            d.op = if (is_byte_imm)
                switch (base_sz) {
                    .bits8 => .or_mem8_imm8,
                    .bits16 => .or_mem16_imm8,
                    .bits32 => .or_mem32_imm8,
                    .bits64 => .or_mem64_imm8,
                }
            else switch (base_sz) {
                .bits8 => .or_mem8_imm8,
                .bits16 => .or_mem16_imm32,
                .bits32 => .or_mem32_imm32,
                .bits64 => .or_mem64_imm32,
            };
            d.addr = rm.addr;
            d.imm = imm;
            d.size = base_sz;
            d.len = @intCast(pos);
            return d;
        }
        const mem_group_ops: [8]Op = .{
            .add_mem8_imm8, .invalid, .invalid, .invalid,
            .invalid,       .invalid, .invalid, .cmp_mem8_imm8,
        };
        const base = mem_group_ops[group_op];
        if (base == .invalid) {
            d.op = .invalid;
            d.len = @as(u8, @intCast(pos));
            return d;
        }
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.addr = rm.addr;
    } else {
        const base = group_ops[group_op];
        const off = @intFromEnum(base_sz) - @intFromEnum(Size.bits8);
        d.op = @enumFromInt(@intFromEnum(base) + off);
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.size = base_sz;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup2Shift(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group_op = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode == 0xC0 or opcode == 0xD0 or opcode == 0xD2;
    const size: Size = if (is_byte) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const uses_cl = opcode == 0xD2 or opcode == 0xD3;

    if (group_op != 0 and group_op != 1 and group_op != 4 and group_op != 5 and group_op != 7) {
        d.op = .invalid;
        d.len = @intCast(pos + 1);
        return d;
    }
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, size);
    const count: u64 = if (opcode == 0xC0 or opcode == 0xC1) blk: {
        if (pos >= bytes.len) return .{};
        const immediate = bytes[pos];
        pos += 1;
        break :blk immediate;
    } else if (uses_cl) 0 else 1;

    if (uses_cl) {
        d.op = if (is_mem)
            switch (group_op) {
                0 => .rol_mem_cl,
                1 => .ror_mem_cl,
                4 => .shl_mem_cl,
                5 => .shr_mem_cl,
                else => .sar_mem_cl,
            }
        else switch (group_op) {
            0 => .rol_reg_cl,
            1 => .ror_reg_cl,
            4 => .shl_reg_cl,
            5 => .shr_reg_cl,
            else => .sar_reg_cl,
        };
    } else if (is_mem) {
        d.op = switch (group_op) {
            0 => .rol_mem_imm,
            1 => .ror_mem_imm,
            4 => .shl_mem_imm,
            5 => .shr_mem_imm,
            else => .sar_mem_imm,
        };
    } else {
        d.op = switch (group_op) {
            0 => .rol_reg_imm,
            1 => .ror_reg_imm,
            4 => .shl_reg_imm,
            5 => .shr_reg_imm,
            else => .sar_reg_imm,
        };
    }
    d.size = size;
    d.imm = count;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
    }
    d.len = @intCast(pos);
    return d;
}

fn decodeMovMemImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    if (((modrm >> 3) & 7) != 0) return .{};
    const is_mem = modrm < 0xC0;

    if (opcode == 0xC6) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);
        if (pos >= bytes.len) return .{};
        d.size = .bits8;
        if (is_mem) {
            d.op = .mov_mem8_imm8;
            d.addr = rm.addr;
        } else {
            d.op = .mov_reg_imm;
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.imm = bytes[pos];
        pos += 1;
    } else {
        const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        d.size = sz;
        if (sz == .bits16) {
            if (pos + 2 > bytes.len) return .{};
            d.op = .mov_mem16_imm16;
            d.imm = std.mem.readInt(u16, bytes[pos..][0..2], .little);
            pos += 2;
        } else if (sz == .bits64) {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem64_imm32;
            const imm32 = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            d.imm = @bitCast(@as(i64, @as(i32, @bitCast(imm32))));
            pos += 4;
        } else {
            if (pos + 4 > bytes.len) return .{};
            d.op = .mov_mem32_imm32;
            d.imm = std.mem.readInt(u32, bytes[pos..][0..4], .little);
            pos += 4;
        }
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.op = .mov_reg_imm;
            d.dst_reg = @enumFromInt(rm.addr);
        }
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeGroup3(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};

    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;
    const sz: Size = if (opcode == 0xF6) .bits8 else if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (group == 2) {
        const base_op: Op = if (is_mem) .not_mem8 else .not_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.len = @intCast(pos);
        return d;
    }

    if (group == 3) {
        const base_op: Op = if (is_mem) .neg_mem8 else .neg_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) {
            d.addr = rm.addr;
        } else {
            d.dst_reg = @enumFromInt(rm.addr);
        }
        d.len = @intCast(pos);
        return d;
    }

    if (group == 4 and !is_mem) {
        d.op = @enumFromInt(@intFromEnum(Op.mul_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        d.dst_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group == 6 and sz != .bits8) {
        const base_op: Op = if (is_mem) .div_mem8 else .div_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }
    if (group == 7 and sz != .bits8) {
        const base_op: Op = if (is_mem) .idiv_mem8 else .idiv_reg8;
        d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
        d.size = sz;
        if (is_mem) d.addr = rm.addr else d.dst_reg = @enumFromInt(rm.addr);
        d.len = @intCast(pos);
        return d;
    }

    if (group != 0 and group != 1) {
        d.op = .invalid;
        d.len = @intCast(pos);
        return d;
    }

    const imm_len: usize = switch (sz) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32, .bits64 => 4,
    };
    if (pos + imm_len > bytes.len) return .{};
    d.imm = switch (sz) {
        .bits8 => bytes[pos],
        .bits16 => std.mem.readInt(u16, bytes[pos..][0..2], .little),
        .bits32 => std.mem.readInt(u32, bytes[pos..][0..4], .little),
        .bits64 => @bitCast(@as(i64, @as(i32, @bitCast(std.mem.readInt(u32, bytes[pos..][0..4], .little))))),
    };
    pos += imm_len;
    const base_op: Op = if (is_mem) .test_mem8_imm8 else .test_reg8_imm8;
    d.op = @enumFromInt(@intFromEnum(base_op) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
    d.size = sz;
    if (is_mem) {
        d.addr = rm.addr;
    } else {
        d.dst_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.len = @intCast(pos);
    return d;
}

fn decodeGroup4_5(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const group = (modrm >> 3) & 7;
    const is_mem = modrm < 0xC0;

    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    if (opcode == 0xFE) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        if (group == 0) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else if (group == 1) {
            if (is_mem) {
                d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.addr = rm.addr;
            } else {
                d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                d.dst_reg = @enumFromInt(rm.addr);
            }
        } else {
            d.op = .invalid;
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    if (opcode == 0xFF) {
        const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);
        switch (group) {
            0 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.inc_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            1 => {
                if (is_mem) {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_mem8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.addr = rm.addr;
                } else {
                    d.op = @enumFromInt(@intFromEnum(Op.dec_reg8) + @intFromEnum(sz) - @intFromEnum(Size.bits8));
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            2 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            3 => {
                if (is_mem) {
                    d.op = .call_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .call_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            4 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            5 => {
                if (is_mem) {
                    d.op = .jmp_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .jmp_reg64;
                    d.dst_reg = @enumFromInt(rm.addr);
                    d.addr = 0;
                }
            },
            6 => {
                if (is_mem) {
                    d.op = .push_mem64;
                    d.addr = rm.addr;
                } else {
                    d.op = .push_reg;
                    d.dst_reg = @enumFromInt(rm.addr);
                }
            },
            else => {
                d.op = .invalid;
            },
        }
        d.len = @as(u8, @intCast(pos));
        return d;
    }

    d.op = .invalid;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeTestRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else if (opcode == 0x84) .bits8 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits8 => .test_mem8_reg8,
            .bits16 => .test_mem16_reg16,
            .bits32 => .test_mem32_reg32,
            .bits64 => .test_mem64_reg64,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits8 => .test_reg8_reg8,
            .bits16 => .test_reg16_reg16,
            .bits32 => .test_reg32_reg32,
            .bits64 => .test_reg64_reg64,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeXchgRmReg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, _: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .xchg_mem32_reg32,
            .bits64 => .xchg_mem64_reg64,
            else => .invalid,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits32 => .xchg_mem32_reg32,
            .bits64 => .xchg_mem64_reg64,
            else => .invalid,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeImulImm(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const imm_is_byte = opcode == 0x6B;
    const imm_size: usize = if (imm_is_byte) 1 else if (sz == .bits16) 2 else 4;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (pos + imm_size > bytes.len) return .{};
    const imm: u64 = if (imm_is_byte)
        @as(u64, @bitCast(@as(i64, @as(i8, @bitCast(bytes[pos])))))
    else if (imm_size == 2)
        std.mem.readInt(u16, bytes[pos..][0..2], .little)
    else
        std.mem.readInt(u32, bytes[pos..][0..4], .little);
    pos += imm_size;

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32_imm8,
            .bits64 => .imul_reg64_mem64_imm8,
            else => .imul_reg32_mem32_imm8,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32_imm8,
            .bits64 => .imul_reg64_reg64_imm8,
            else => .imul_reg32_reg32_imm8,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.imm = imm;
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeImulTwoOp(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_mem32,
            .bits64 => .imul_reg64_mem64,
            else => .imul_reg32_mem32,
        };
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = switch (sz) {
            .bits32 => .imul_reg32_reg32,
            .bits64 => .imul_reg64_reg64,
            else => .imul_reg32_reg32,
        };
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeCmpxchg(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .cmpxchg_mem32_reg32,
            .bits64 => .cmpxchg_mem64_reg64,
            else => .cmpxchg_mem32_reg32,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    } else {
        d.op = switch (sz) {
            .bits32 => .cmpxchg_mem32_reg32,
            .bits64 => .cmpxchg_mem64_reg64,
            else => .cmpxchg_mem32_reg32,
        };
        d.dst_reg = @enumFromInt(rm.addr);
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovzx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xB6;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movzx_reg32_mem8 else .movzx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovsx(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    const is_mem = modrm < 0xC0;
    const is_byte = opcode2 == 0xBE;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.addr = rm.addr;
    } else {
        d.op = if (is_byte) .movsx_reg32_mem8 else .movsx_reg32_mem16;
        d.dst_reg = rm.reg;
        d.src_reg = @enumFromInt(rm.addr);
        d.is_reg_form = true;
    }
    d.size = sz;

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeXadd(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = opcode2;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const sz: Size = if (rex_w) .bits64 else if (has_66) .bits16 else .bits32;
    d.size = sz;
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, sz);

    if (is_mem) {
        d.op = switch (sz) {
            .bits32 => .xadd_mem32_reg32,
            .bits64 => .xadd_mem64_reg64,
            else => .xadd_mem32_reg32,
        };
        d.addr = rm.addr;
        d.src_reg = rm.reg;
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeSetcc(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits8);

    const setcc_conditions: [16]Cond = .{
        .o, .no, .b, .ae, .e, .ne, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g,
    };

    if (is_mem) {
        d.op = .setcc_mem8;
        d.addr = rm.addr;
    } else {
        d.op = .setcc_reg8;
        d.dst_reg = @enumFromInt(rm.addr);
    }

    d.cond = setcc_conditions[opcode2 & 0x0F];
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovupsMovss(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, has_f2: bool, has_f3: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const to_reg = opcode2 == 0x10;
    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);

    // Scalar MOVSS/MOVSD need lane-preserving semantics. MOVUPS transfers the
    // full register and is required by Xbyak's feature-mask bookkeeping.
    if (has_f2 or has_f3) {
        d.op = .nop;
    } else if (to_reg) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movups_xmm_mem;
            d.addr = rm.addr;
        } else {
            d.op = .movups_xmm_xmm;
            d.xmm_src = @intCast(rm.addr);
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movups_mem_xmm;
            d.addr = rm.addr;
        } else {
            d.op = .movups_xmm_xmm;
            d.xmm_dst = @intCast(rm.addr);
        }
    }
    d.len = @as(u8, @intCast(pos));
    return d;
}

fn decodeMovaps(bytes: []const u8, start_pos: usize, rex_r: bool, rex_x: bool, rex_b: bool, rex_w: bool, has_66: bool, opcode2: u8) DecodedInsn {
    _ = rex_w;
    _ = has_66;
    var d = DecodedInsn{};
    var pos = start_pos + 1;
    if (pos >= bytes.len) return .{};
    const modrm = bytes[pos];
    const is_mem = modrm < 0xC0;
    const to_reg = opcode2 == 0x28;

    const rm = readModRM(&d, bytes, &pos, rex_r, rex_x, rex_b, .bits64);

    if (to_reg) {
        d.xmm_dst = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movaps_xmm_mem;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
            d.xmm_src = @intCast(rm.addr);
        }
    } else {
        d.xmm_src = @intFromEnum(rm.reg);
        if (is_mem) {
            d.op = .movaps_mem_xmm;
            d.addr = rm.addr;
        } else {
            d.op = .movaps_xmm_xmm;
            d.xmm_dst = @intCast(rm.addr);
        }
    }

    d.len = @as(u8, @intCast(pos));
    return d;
}

test "decode Xbyak shl ecx immediate" {
    const decoded = decodeInsn(&[_]u8{ 0xC1, 0xE1, 0x08 });
    try std.testing.expectEqual(Op.shl_reg_imm, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 8), decoded.imm);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode group two implicit and arithmetic shifts" {
    const shr = decodeInsn(&[_]u8{ 0xD1, 0xE9 });
    try std.testing.expectEqual(Op.shr_reg_imm, shr.op);
    try std.testing.expectEqual(@as(u64, 1), shr.imm);
    try std.testing.expectEqual(@as(u8, 2), shr.len);

    const sar = decodeInsn(&[_]u8{ 0x48, 0xC1, 0xFE, 0x03 });
    try std.testing.expectEqual(Op.sar_reg_imm, sar.op);
    try std.testing.expectEqual(Size.bits64, sar.size);
    try std.testing.expectEqual(RegId.dh_si_esi_rsi, sar.dst_reg);
    try std.testing.expectEqual(@as(u64, 3), sar.imm);
    try std.testing.expectEqual(@as(u8, 4), sar.len);

    const shr_cl = decodeInsn(&[_]u8{ 0xD3, 0xE8 });
    try std.testing.expectEqual(Op.shr_reg_cl, shr_cl.op);
    try std.testing.expectEqual(Size.bits32, shr_cl.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, shr_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), shr_cl.len);

    const sar_cl = decodeInsn(&[_]u8{ 0xD3, 0xF8 });
    try std.testing.expectEqual(Op.sar_reg_cl, sar_cl.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sar_cl.dst_reg);
}

test "decode group two rotate forms" {
    const fmt_ror = decodeInsn(&[_]u8{ 0xD3, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_cl, fmt_ror.op);
    try std.testing.expectEqual(Size.bits32, fmt_ror.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_ror.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), fmt_ror.len);

    const rol_byte_memory = decodeInsn(&[_]u8{ 0xC0, 0x07, 0x03 });
    try std.testing.expectEqual(Op.rol_mem_imm, rol_byte_memory.op);
    try std.testing.expectEqual(Size.bits8, rol_byte_memory.size);
    try std.testing.expectEqual(@as(u64, 3), rol_byte_memory.imm);

    const ror_rax = decodeInsn(&[_]u8{ 0x48, 0xD1, 0xC8 });
    try std.testing.expectEqual(Op.ror_reg_imm, ror_rax.op);
    try std.testing.expectEqual(Size.bits64, ror_rax.size);
    try std.testing.expectEqual(@as(u64, 1), ror_rax.imm);
}

test "decode register MOVZX without consuming the following instruction" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xB6, 0xC0, 0x48, 0x83, 0xC4, 0x30 });
    try std.testing.expectEqual(Op.movzx_reg32_mem8, decoded.op);
    try std.testing.expectEqual(Size.bits32, decoded.size);
    try std.testing.expect(decoded.is_reg_form);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.src_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode MOVSX memory and accumulator byte immediate forms" {
    const movsx = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBE, 0x48, 0x03 });
    try std.testing.expectEqual(Op.movsx_reg32_mem8, movsx.op);
    try std.testing.expectEqual(Size.bits64, movsx.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, movsx.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, movsx.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), movsx.addr);
    try std.testing.expectEqual(@as(u8, 5), movsx.len);

    const and_al = decodeInsn(&[_]u8{ 0x24, 0x01 });
    try std.testing.expectEqual(Op.and_reg8_imm8, and_al.op);
    try std.testing.expectEqual(Size.bits8, and_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), and_al.imm);
    try std.testing.expectEqual(@as(u8, 2), and_al.len);
}

test "decode accumulator TEST immediate forms" {
    const test_al = decodeInsn(&[_]u8{ 0xA8, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_al.op);
    try std.testing.expectEqual(Size.bits8, test_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, test_al.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_al.imm);
    try std.testing.expectEqual(@as(u8, 2), test_al.len);

    const test_rax = decodeInsn(&[_]u8{ 0x48, 0xA9, 0x00, 0x00, 0x00, 0x80 });
    try std.testing.expectEqual(Op.test_reg64_imm32, test_rax.op);
    try std.testing.expectEqual(Size.bits64, test_rax.size);
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_8000_0000), test_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), test_rax.len);
}

test "decode accumulator immediate arithmetic widths" {
    const add_rax = decodeInsn(&[_]u8{ 0x48, 0x05, 0xAB, 0x00, 0x00, 0x00 });
    try std.testing.expectEqual(Op.add_accum_imm, add_rax.op);
    try std.testing.expectEqual(Size.bits64, add_rax.size);
    try std.testing.expectEqual(@as(u64, 0xAB), add_rax.imm);
    try std.testing.expectEqual(@as(u8, 6), add_rax.len);

    const sub_ax = decodeInsn(&[_]u8{ 0x66, 0x2D, 0x34, 0x12 });
    try std.testing.expectEqual(Op.sub_accum_imm, sub_ax.op);
    try std.testing.expectEqual(Size.bits16, sub_ax.size);
    try std.testing.expectEqual(@as(u64, 0x1234), sub_ax.imm);

    const cmp_rax_negative = decodeInsn(&[_]u8{ 0x48, 0x3D, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.cmp_accum_imm, cmp_rax_negative.op);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), cmp_rax_negative.imm);
}

test "decode full near conditional jump range" {
    const jc = decodeInsn(&[_]u8{ 0x0F, 0x82, 0xA7, 0x01, 0x00, 0x00 });
    try std.testing.expectEqual(Op.jcc_rel32, jc.op);
    try std.testing.expectEqual(Cond.b, jc.cond);
    try std.testing.expectEqual(@as(u64, 0x1A7), jc.addr);
    try std.testing.expect(jc.rip_relative);
    try std.testing.expectEqual(@as(u8, 6), jc.len);
}

test "decode both directions of 64-bit AND memory operands" {
    const load_and = decodeInsn(&[_]u8{ 0x48, 0x23, 0x08 });
    try std.testing.expectEqual(Op.and_reg64_mem64, load_and.op);
    try std.testing.expectEqual(Size.bits64, load_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_and.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), load_and.len);

    const store_and = decodeInsn(&[_]u8{ 0x48, 0x21, 0x08 });
    try std.testing.expectEqual(Op.and_mem64_reg64, store_and.op);
    try std.testing.expectEqual(Size.bits64, store_and.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, store_and.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_and.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), store_and.len);
}

test "decode arithmetic byte width and operand direction" {
    const xor_al = decodeInsn(&[_]u8{ 0x30, 0xC0 });
    try std.testing.expectEqual(Op.xor_reg8_reg8, xor_al.op);
    try std.testing.expectEqual(Size.bits8, xor_al.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, xor_al.src_reg);

    const sub_mem = decodeInsn(&[_]u8{ 0x29, 0x08 });
    try std.testing.expectEqual(Op.sub_mem32_reg32, sub_mem.op);
    try std.testing.expectEqual(Size.bits32, sub_mem.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, sub_mem.src_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, sub_mem.sib_base_reg);
}

test "decode group three TEST register immediate" {
    const test_cl = decodeInsn(&[_]u8{ 0xF6, 0xC1, 0x01 });
    try std.testing.expectEqual(Op.test_reg8_imm8, test_cl.op);
    try std.testing.expectEqual(Size.bits8, test_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, test_cl.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), test_cl.imm);
    try std.testing.expectEqual(@as(u8, 3), test_cl.len);
}

test "decode CPUID and XGETBV" {
    const cpuid = decodeInsn(&[_]u8{ 0x0F, 0xA2 });
    try std.testing.expectEqual(Op.cpuid, cpuid.op);
    try std.testing.expectEqual(@as(u8, 2), cpuid.len);

    const xgetbv = decodeInsn(&[_]u8{ 0x0F, 0x01, 0xD0 });
    try std.testing.expectEqual(Op.xgetbv, xgetbv.op);
    try std.testing.expectEqual(@as(u8, 3), xgetbv.len);
}

test "decode non-W REX prefixes used by CPUID result copies" {
    const mov_r9d_eax = decodeInsn(&[_]u8{ 0x41, 0x89, 0xC1 });
    try std.testing.expectEqual(Op.mov_reg32_reg32, mov_r9d_eax.op);
    try std.testing.expectEqual(Size.bits32, mov_r9d_eax.size);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_r9d_eax.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, mov_r9d_eax.src_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_r9d_eax.len);

    const mov_mem_r9d = decodeInsn(&[_]u8{ 0x45, 0x89, 0x08 });
    try std.testing.expectEqual(Op.mov_mem32_reg32, mov_mem_r9d.op);
    try std.testing.expectEqual(RegId.r9b_r9w_r9d_r9, mov_mem_r9d.src_reg);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, mov_mem_r9d.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), mov_mem_r9d.len);
}

test "decode Xbyak unaligned feature-mask copy" {
    const load = decodeInsn(&[_]u8{ 0x0F, 0x10, 0x00 });
    try std.testing.expectEqual(Op.movups_xmm_mem, load.op);
    try std.testing.expectEqual(@as(u8, 0), load.xmm_dst);
    try std.testing.expectEqual(@as(u8, 3), load.len);

    const store = decodeInsn(&[_]u8{ 0x0F, 0x29, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.movaps_mem_xmm, store.op);
    try std.testing.expectEqual(@as(u8, 0), store.xmm_src);
    try std.testing.expectEqual(@as(u8, 4), store.len);
}

test "decode 128-bit VEX move families" {
    const load_dqu = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_xmm_mem, load_dqu.op);
    try std.testing.expectEqual(@as(u8, 0), load_dqu.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_dqu.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 4), load_dqu.len);

    const store_dqa = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x7F, 0x45, 0xF0 });
    try std.testing.expectEqual(Op.vmovdqa_mem_xmm, store_dqa.op);
    try std.testing.expectEqual(@as(u8, 0), store_dqa.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_dqa.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -16))), store_dqa.addr);
    try std.testing.expectEqual(@as(u8, 5), store_dqa.len);

    const register_ups = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x10, 0xCA });
    try std.testing.expectEqual(Op.vmovups_xmm_xmm, register_ups.op);
    try std.testing.expectEqual(@as(u8, 1), register_ups.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), register_ups.xmm_src);

    const load_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x10, 0x01 });
    try std.testing.expectEqual(Op.vmovss_xmm_mem, load_ss.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, load_ss.sib_base_reg);

    const store_ss = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x11, 0x00 });
    try std.testing.expectEqual(Op.vmovss_mem_xmm, store_ss.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, store_ss.sib_base_reg);

    const load_sd = decodeInsn(&[_]u8{ 0xC5, 0xFB, 0x10, 0x02 });
    try std.testing.expectEqual(Op.vmovsd_xmm_mem, load_sd.op);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, load_sd.sib_base_reg);
}

test "decode VEX dword move and byte insertion" {
    const move_register = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0xC0 });
    try std.testing.expectEqual(Op.vmovd_xmm_reg32, move_register.op);
    try std.testing.expectEqual(@as(u8, 0), move_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, move_register.src_reg);
    try std.testing.expectEqual(@as(u8, 4), move_register.len);

    const move_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x6E, 0x09 });
    try std.testing.expectEqual(Op.vmovd_xmm_mem32, move_memory.op);
    try std.testing.expectEqual(@as(u8, 1), move_memory.xmm_dst);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, move_memory.sib_base_reg);

    const insert_register = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0xC0, 0x0F });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_reg32, insert_register.op);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), insert_register.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_register.src_reg);
    try std.testing.expectEqual(@as(u64, 15), insert_register.imm);
    try std.testing.expectEqual(@as(u8, 6), insert_register.len);

    const insert_memory = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x20, 0x00, 0x05 });
    try std.testing.expectEqual(Op.vpinsrb_xmm_xmm_mem8, insert_memory.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, insert_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 5), insert_memory.imm);

    const shuffle = decodeInsn(&[_]u8{ 0xC4, 0xE2, 0x79, 0x00, 0xC1 });
    try std.testing.expectEqual(Op.vpshufb, shuffle.op);
    try std.testing.expect(!shuffle.vector_256);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), shuffle.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), shuffle.xmm_src2);
    try std.testing.expect(shuffle.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), shuffle.len);
}

test "decode VEX qword moves between XMM general registers and memory" {
    const failing_signbit_move = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0xC0 });
    try std.testing.expectEqual(Op.vmovq_reg64_xmm, failing_signbit_move.op);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, failing_signbit_move.dst_reg);
    try std.testing.expectEqual(@as(u8, 0), failing_signbit_move.xmm_src);
    try std.testing.expectEqual(@as(u8, 5), failing_signbit_move.len);

    const load_register = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x6E, 0xC8 });
    try std.testing.expectEqual(Op.vmovq_xmm_reg64, load_register.op);
    try std.testing.expectEqual(@as(u8, 1), load_register.xmm_dst);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, load_register.src_reg);

    const store_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xF9, 0x7E, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.vmovq_mem64_xmm, store_memory.op);
    try std.testing.expectEqual(@as(u8, 0), store_memory.xmm_src);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, store_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), store_memory.addr);
}

test "decode 256-bit VEX packed moves" {
    const decoded = decodeInsn(&[_]u8{ 0xC5, 0xFE, 0x6F, 0x00 });
    try std.testing.expectEqual(Op.vmovdqu_ymm_mem, decoded.op);

    const copy_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x10, 0x00 });
    try std.testing.expectEqual(Op.vmovups_ymm_mem, copy_state.op);

    const store_state = decodeInsn(&[_]u8{ 0xC5, 0xFC, 0x11, 0x07 });
    try std.testing.expectEqual(Op.vmovups_mem_ymm, store_state.op);

    const zero_upper = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x77 });
    try std.testing.expectEqual(Op.vzeroupper, zero_upper.op);
    try std.testing.expectEqual(@as(u8, 3), zero_upper.len);
}

test "decode three-byte VEX signed integer scalar conversions" {
    const to_float = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2A, 0xC0 });
    try std.testing.expectEqual(Op.vcvtsi2ss_xmm_reg, to_float.op);
    try std.testing.expectEqual(Size.bits64, to_float.size);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), to_float.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, to_float.src_reg);
    try std.testing.expectEqual(@as(u8, 5), to_float.len);

    const to_double = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2A, 0x09 });
    try std.testing.expectEqual(Op.vcvtsi2sd_xmm_mem, to_double.op);
    try std.testing.expectEqual(Size.bits32, to_double.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, to_double.sib_base_reg);
}

test "decode VEX scalar and packed arithmetic" {
    const boundary = decodeInsn(&[_]u8{ 0xC5, 0xFA, 0x58, 0xC0 });
    try std.testing.expectEqual(Op.vaddss, boundary.op);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), boundary.xmm_src2);
    try std.testing.expect(boundary.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), boundary.len);

    const packed_256 = decodeInsn(&[_]u8{ 0xC5, 0xEC, 0x59, 0xCB });
    try std.testing.expectEqual(Op.vmulps, packed_256.op);
    try std.testing.expectEqual(@as(u8, 1), packed_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), packed_256.xmm_src);
    try std.testing.expectEqual(@as(u8, 3), packed_256.xmm_src2);
    try std.testing.expect(packed_256.vector_256);

    const scalar_memory = decodeInsn(&[_]u8{ 0xC5, 0xEB, 0x5E, 0x08 });
    try std.testing.expectEqual(Op.vdivsd, scalar_memory.op);
    try std.testing.expectEqual(@as(u8, 1), scalar_memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), scalar_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, scalar_memory.sib_base_reg);
    try std.testing.expect(!scalar_memory.is_reg_form);
}

test "decode VEX bitwise vector operations" {
    const zero = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x57, 0xC0 });
    try std.testing.expectEqual(Op.vxorps, zero.op);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), zero.xmm_src2);
    try std.testing.expect(!zero.vector_256);

    const and_not_256 = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x55, 0x08 });
    try std.testing.expectEqual(Op.vandnpd, and_not_256.op);
    try std.testing.expectEqual(@as(u8, 1), and_not_256.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), and_not_256.xmm_src);
    try std.testing.expect(and_not_256.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, and_not_256.sib_base_reg);
}

test "decode VPCMPEQD register memory and extended-register forms" {
    const failing = decodeInsn(&[_]u8{ 0xC5, 0xFD, 0x76, 0xC0 });
    try std.testing.expectEqual(Op.vpcmpeqd, failing.op);
    try std.testing.expect(failing.vector_256);
    try std.testing.expect(failing.is_reg_form);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src);
    try std.testing.expectEqual(@as(u8, 0), failing.xmm_src2);
    try std.testing.expectEqual(@as(u8, 4), failing.len);

    const memory = decodeInsn(&[_]u8{ 0xC5, 0xED, 0x76, 0x08 });
    try std.testing.expectEqual(Op.vpcmpeqd, memory.op);
    try std.testing.expect(memory.vector_256);
    try std.testing.expect(!memory.is_reg_form);
    try std.testing.expectEqual(@as(u8, 1), memory.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.sib_base_reg);

    const extended = decodeInsn(&[_]u8{ 0xC4, 0x41, 0x6D, 0x76, 0xC8 });
    try std.testing.expectEqual(Op.vpcmpeqd, extended.op);
    try std.testing.expectEqual(@as(u8, 9), extended.xmm_dst);
    try std.testing.expectEqual(@as(u8, 2), extended.xmm_src);
    try std.testing.expectEqual(@as(u8, 8), extended.xmm_src2);
}

test "VPCMPEQD compares independent dword lanes" {
    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    std.mem.writeInt(u32, lhs[0..4], 7, .little);
    std.mem.writeInt(u32, rhs[0..4], 7, .little);
    std.mem.writeInt(u32, lhs[4..8], 9, .little);
    std.mem.writeInt(u32, rhs[4..8], 10, .little);
    const result = compareEqualDwords(lhs, rhs);
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, result[4..8], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[8..12], .little));
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, result[12..16], .little));
}

test "decode VEX unordered scalar comparisons" {
    const single = decodeInsn(&[_]u8{ 0xC5, 0xF8, 0x2E, 0xC1 });
    try std.testing.expectEqual(Op.vucomiss, single.op);
    try std.testing.expectEqual(@as(u8, 0), single.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), single.xmm_src2);
    try std.testing.expect(single.is_reg_form);
    try std.testing.expectEqual(@as(u8, 4), single.len);

    const double_memory = decodeInsn(&[_]u8{ 0xC5, 0xF9, 0x2F, 0x08 });
    try std.testing.expectEqual(Op.vucomisd, double_memory.op);
    try std.testing.expectEqual(@as(u8, 1), double_memory.xmm_src);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, double_memory.sib_base_reg);
    try std.testing.expect(!double_memory.is_reg_form);
}

test "decode VEX scalar and packed rounding" {
    const ceiling = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x79, 0x0A, 0xC1, 0x0A });
    try std.testing.expectEqual(Op.vroundss, ceiling.op);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_dst);
    try std.testing.expectEqual(@as(u8, 0), ceiling.xmm_src);
    try std.testing.expectEqual(@as(u8, 1), ceiling.xmm_src2);
    try std.testing.expectEqual(@as(u64, 0x0A), ceiling.imm);
    try std.testing.expectEqual(@as(u8, 6), ceiling.len);

    const packed_round = decodeInsn(&[_]u8{ 0xC4, 0xE3, 0x7D, 0x08, 0x00, 0x03 });
    try std.testing.expectEqual(Op.vroundps, packed_round.op);
    try std.testing.expect(packed_round.vector_256);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, packed_round.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 3), packed_round.imm);
}

test "VEX rounding modes include ties-to-even" {
    try std.testing.expectEqual(@as(f32, 2.0), roundVexFloat(f32, 2.5, 0));
    try std.testing.expectEqual(@as(f32, 4.0), roundVexFloat(f32, 3.5, 0));
    try std.testing.expectEqual(@as(f32, -3.0), roundVexFloat(f32, -2.1, 1));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.1, 2));
    try std.testing.expectEqual(@as(f32, -2.0), roundVexFloat(f32, -2.9, 3));
}

test "decode VEX scalar float to signed integer conversions" {
    const truncate_to_64 = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0xFA, 0x2C, 0xC1 });
    try std.testing.expectEqual(Op.vcvttss2si, truncate_to_64.op);
    try std.testing.expectEqual(Size.bits64, truncate_to_64.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, truncate_to_64.dst_reg);
    try std.testing.expectEqual(@as(u8, 1), truncate_to_64.xmm_src);
    try std.testing.expect(truncate_to_64.is_reg_form);
    try std.testing.expectEqual(@as(u8, 5), truncate_to_64.len);

    const round_double_memory = decodeInsn(&[_]u8{ 0xC4, 0xE1, 0x7B, 0x2D, 0x08 });
    try std.testing.expectEqual(Op.vcvtsd2si, round_double_memory.op);
    try std.testing.expectEqual(Size.bits32, round_double_memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, round_double_memory.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, round_double_memory.sib_base_reg);
}

test "VEX float to signed conversion handles rounding and overflow" {
    try std.testing.expectEqual(@as(u64, 3), convertVexFloatToSigned(f32, 3.9, .bits64, true));
    try std.testing.expectEqual(@as(u64, 4), convertVexFloatToSigned(f32, 3.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 2), convertVexFloatToSigned(f32, 2.5, .bits64, false));
    try std.testing.expectEqual(@as(u64, 0x8000_0000), convertVexFloatToSigned(f64, std.math.nan(f64), .bits32, true));
    try std.testing.expectEqual(@as(u64, 0x8000_0000_0000_0000), convertVexFloatToSigned(f64, 1.0e30, .bits64, true));
}

test "decode MOVSXD from memory" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x63, 0x09 });
    try std.testing.expectEqual(Op.movsxd_reg64_mem32, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode unsigned 64-bit register division" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg64, decoded.op);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), decoded.len);
}

test "decode signed and unsigned 32-bit register division" {
    const signed = decodeInsn(&[_]u8{ 0xF7, 0xF9 });
    try std.testing.expectEqual(Op.idiv_reg32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, signed.dst_reg);

    const unsigned = decodeInsn(&[_]u8{ 0xF7, 0xF1 });
    try std.testing.expectEqual(Op.div_reg32, unsigned.op);
    try std.testing.expectEqual(Size.bits32, unsigned.size);
}

test "decode signed and unsigned memory division" {
    const unsigned = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x75, 0xF8 });
    try std.testing.expectEqual(Op.div_mem64, unsigned.op);
    try std.testing.expectEqual(Size.bits64, unsigned.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, unsigned.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), unsigned.addr);
    try std.testing.expectEqual(@as(u8, 4), unsigned.len);

    const signed = decodeInsn(&[_]u8{ 0xF7, 0x7B, 0x10 });
    try std.testing.expectEqual(Op.idiv_mem32, signed.op);
    try std.testing.expectEqual(Size.bits32, signed.size);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, signed.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 0x10), signed.addr);
    try std.testing.expectEqual(@as(u8, 3), signed.len);
}

test "decode group three NOT register and memory forms" {
    const register = decodeInsn(&[_]u8{ 0xF6, 0xD1 });
    try std.testing.expectEqual(Op.not_reg8, register.op);
    try std.testing.expectEqual(Size.bits8, register.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x55, 0xF8 });
    try std.testing.expectEqual(Op.not_mem64, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), memory.addr);
}

test "decode group three NEG register and memory forms" {
    const failing_neg_cl = decodeInsn(&[_]u8{ 0xF6, 0xD9 });
    try std.testing.expectEqual(Op.neg_reg8, failing_neg_cl.op);
    try std.testing.expectEqual(Size.bits8, failing_neg_cl.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, failing_neg_cl.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), failing_neg_cl.len);

    const neg_qword_memory = decodeInsn(&[_]u8{ 0x48, 0xF7, 0x5D, 0xF8 });
    try std.testing.expectEqual(Op.neg_mem64, neg_qword_memory.op);
    try std.testing.expectEqual(Size.bits64, neg_qword_memory.size);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, neg_qword_memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, @bitCast(@as(i64, -8))), neg_qword_memory.addr);
}

test "decode group three unsigned multiply register widths" {
    const multiply64 = decodeInsn(&[_]u8{ 0x48, 0xF7, 0xE1 });
    try std.testing.expectEqual(Op.mul_reg64, multiply64.op);
    try std.testing.expectEqual(Size.bits64, multiply64.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, multiply64.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), multiply64.len);

    const multiply8 = decodeInsn(&[_]u8{ 0xF6, 0xE2 });
    try std.testing.expectEqual(Op.mul_reg8, multiply8.op);
    try std.testing.expectEqual(Size.bits8, multiply8.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, multiply8.dst_reg);
}

test "decode carry flag control instructions" {
    try std.testing.expectEqual(Op.cmc, decodeInsn(&[_]u8{0xF5}).op);
    try std.testing.expectEqual(Op.clc, decodeInsn(&[_]u8{0xF8}).op);
    try std.testing.expectEqual(Op.stc, decodeInsn(&[_]u8{0xF9}).op);
}

test "decode bit scan and count instructions without losing ModRM" {
    const fmt_bsr = decodeInsn(&[_]u8{ 0x48, 0x0F, 0xBD, 0xC0 });
    try std.testing.expectEqual(Op.bsr_reg_reg, fmt_bsr.op);
    try std.testing.expectEqual(Size.bits64, fmt_bsr.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, fmt_bsr.src_reg);
    try std.testing.expectEqual(@as(u8, 4), fmt_bsr.len);

    const memory_bsf = decodeInsn(&[_]u8{ 0x0F, 0xBC, 0x48, 0x08 });
    try std.testing.expectEqual(Op.bsf_reg_mem, memory_bsf.op);
    try std.testing.expectEqual(Size.bits32, memory_bsf.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory_bsf.dst_reg);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory_bsf.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory_bsf.addr);
    try std.testing.expectEqual(@as(u8, 4), memory_bsf.len);

    const lzcnt = decodeInsn(&[_]u8{ 0xF3, 0x48, 0x0F, 0xBD, 0xC3 });
    try std.testing.expectEqual(Op.lzcnt_reg_reg, lzcnt.op);
    try std.testing.expectEqual(Size.bits64, lzcnt.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, lzcnt.dst_reg);
    try std.testing.expectEqual(RegId.bl_bx_ebx_rbx, lzcnt.src_reg);
    try std.testing.expectEqual(@as(u8, 5), lzcnt.len);
}

test "decode BSWAP register family" {
    const initializer_bswap = decodeInsn(&[_]u8{ 0x0F, 0xC8 });
    try std.testing.expectEqual(Op.bswap_reg, initializer_bswap.op);
    try std.testing.expectEqual(Size.bits32, initializer_bswap.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, initializer_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 2), initializer_bswap.len);

    const extended_bswap = decodeInsn(&[_]u8{ 0x49, 0x0F, 0xCF });
    try std.testing.expectEqual(Op.bswap_reg, extended_bswap.op);
    try std.testing.expectEqual(Size.bits64, extended_bswap.size);
    try std.testing.expectEqual(RegId.r15b_r15w_r15d_r15, extended_bswap.dst_reg);
    try std.testing.expectEqual(@as(u8, 3), extended_bswap.len);
}

test "bit scan and count semantics cover zero and operand width" {
    const bsr = bitScan(.bits64, .bsr, 0x8000_0000_0000_0000);
    try std.testing.expectEqual(@as(u64, 63), bsr.value);
    try std.testing.expect(bsr.write_destination);
    try std.testing.expect(!bsr.zero_flag);
    try std.testing.expectEqual(@as(?bool, null), bsr.carry_flag);

    const empty_bsf = bitScan(.bits32, .bsf, 0);
    try std.testing.expect(!empty_bsf.write_destination);
    try std.testing.expect(empty_bsf.zero_flag);

    const empty_tzcnt = bitScan(.bits16, .tzcnt, 0);
    try std.testing.expectEqual(@as(u64, 16), empty_tzcnt.value);
    try std.testing.expectEqual(@as(?bool, true), empty_tzcnt.carry_flag);

    const lzcnt = bitScan(.bits32, .lzcnt, 0x0000_0100);
    try std.testing.expectEqual(@as(u64, 23), lzcnt.value);
    try std.testing.expectEqual(@as(?bool, false), lzcnt.carry_flag);
}

test "unknown two-byte opcode is rejected at its real boundary" {
    const decoded = decodeInsn(&[_]u8{ 0x0F, 0xFF, 0xC0 });
    try std.testing.expectEqual(Op.invalid, decoded.op);
    try std.testing.expectEqual(@as(u8, 0), decoded.len);
}

test "decode conditional moves without losing the ModRM byte" {
    const register = decodeInsn(&[_]u8{ 0x0F, 0x42, 0xC1 });
    try std.testing.expectEqual(Op.cmovcc_reg_reg, register.op);
    try std.testing.expectEqual(Cond.b, register.cond);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, register.dst_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, register.src_reg);
    try std.testing.expectEqual(@as(u8, 3), register.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x0F, 0x45, 0x45, 0xF8 });
    try std.testing.expectEqual(Op.cmovcc_reg_mem, memory.op);
    try std.testing.expectEqual(Cond.ne, memory.cond);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, memory.dst_reg);
    try std.testing.expectEqual(RegId.ch_bp_ebp_rbp, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64) - 7), memory.addr);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "decode 64-bit OR register immediate without aliasing memory opcodes" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0x83, 0xC9, 0x01 });
    try std.testing.expectEqual(Op.or_reg64_imm8, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, decoded.dst_reg);
    try std.testing.expectEqual(@as(u64, 1), decoded.imm);
    try std.testing.expectEqual(@as(u8, 4), decoded.len);

    const memory = decodeInsn(&[_]u8{ 0x48, 0x83, 0x49, 0x08, 0x01 });
    try std.testing.expectEqual(Op.or_mem64_imm8, memory.op);
    try std.testing.expectEqual(Size.bits64, memory.size);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, memory.sib_base_reg);
    try std.testing.expectEqual(@as(u64, 8), memory.addr);
    try std.testing.expectEqual(@as(u64, 1), memory.imm);
    try std.testing.expectEqual(@as(u8, 5), memory.len);
}

test "dyld data bindings materialize callable constant and GOT slots" {
    const constant_section = macho_metadata.Section{
        .name = "__const",
        .segment_name = "__DATA_CONST",
        .address = 0x1000,
        .size = 0x100,
        .file_offset = 0,
        .flags = 0,
        .indirect_symbol_start = 0,
        .stub_size = 0,
    };
    var got_section = constant_section;
    got_section.name = "__got";

    try std.testing.expect(MachOState.isCallableConstantBinding(
        constant_section,
        "__ZNKSt3__123__match_any_but_newlineIcE6__execERNS_7__stateIcEE",
        false,
    ));
    try std.testing.expect(MachOState.isCallableConstantBinding(constant_section, "_strcmp", true));
    try std.testing.expect(!MachOState.isCallableConstantBinding(constant_section, "__ZTVN10__cxxabiv117__class_type_infoE", false));
    try std.testing.expect(MachOState.isCallableConstantBinding(got_section, "_strcmp", true));
    try std.testing.expect(!MachOState.isCallableConstantBinding(got_section, "___stack_chk_guard", false));
    try std.testing.expect(MachOState.bindingRequiresBoundThunk(got_section));
    try std.testing.expect(!MachOState.bindingRequiresBoundThunk(constant_section));
}

test "Mach-O PAGEZERO is excluded from guest memory" {
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0));
    try std.testing.expectEqual(@as(?u64, null), mappedOffset(0, 0x2000_0000, 0x4000, 0x30));
    try std.testing.expectEqual(@as(?u64, 0x4000), mappedOffset(0, 0x2000_0000, 0x4000, 0x4000));
}

test "decode compiler long NOP with segment override" {
    const decoded = decodeInsn(&[_]u8{ 0x66, 0x66, 0x2E, 0x0F, 0x1F, 0x84, 0x00, 0, 0, 0, 0 });
    try std.testing.expectEqual(Op.nop, decoded.op);
    try std.testing.expectEqual(@as(u8, 11), decoded.len);
}

test "decode C6 and C7 register immediate forms" {
    const byte_move = decodeInsn(&[_]u8{ 0x41, 0xC6, 0xC0, 0x7F });
    try std.testing.expectEqual(Op.mov_reg_imm, byte_move.op);
    try std.testing.expectEqual(Size.bits8, byte_move.size);
    try std.testing.expectEqual(RegId.r8b_r8w_r8d_r8, byte_move.dst_reg);
    try std.testing.expectEqual(@as(u64, 0x7F), byte_move.imm);

    const max_unsigned = decodeInsn(&[_]u8{ 0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_reg_imm, max_unsigned.op);
    try std.testing.expectEqual(Size.bits64, max_unsigned.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, max_unsigned.dst_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), max_unsigned.imm);
    try std.testing.expectEqual(@as(u8, 7), max_unsigned.len);
}

test "decode C7 memory immediate sign extends to 64 bits" {
    const decoded = decodeInsn(&[_]u8{ 0x48, 0xC7, 0x00, 0xFF, 0xFF, 0xFF, 0xFF });
    try std.testing.expectEqual(Op.mov_mem64_imm32, decoded.op);
    try std.testing.expectEqual(Size.bits64, decoded.size);
    try std.testing.expectEqual(RegId.al_ax_eax_rax, decoded.sib_base_reg);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), decoded.imm);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len < 2) {
        std.debug.print("usage: macho_processor <binary> [args...]\n", .{});
        std.process.exit(1);
    }

    const exit_code = try loadAndRun(init.io, allocator, .{
        .path = args[1],
        .args = args[2..],
    });
    const process_status: u8 = if (exit_code <= std.math.maxInt(u8)) @intCast(exit_code) else UNSUPPORTED_RUNTIME_EXIT_CODE;
    if (process_status != exit_code) {
        std.debug.print("macho-processor: normalized non-status exit value 0x{x} to {d}\n", .{ exit_code, process_status });
    }
    std.process.exit(process_status);
}
