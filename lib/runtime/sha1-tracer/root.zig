const std = @import("std");

/// Tracks SHA-1 function execution for diagnostic purposes.
/// Pure data struct with methods that take a Sha1TracerContext for access
/// to guest memory, symbol lookup, and logging via callbacks.
pub const Sha1Tracer = struct {
    /// Master enable — always on, negligible overhead.
    enabled: bool = true,
    /// Current call depth (0 = top level).
    depth: u32 = 0,
    /// RIP of the current function's entry point.
    entry_rip: u64 = 0,
    /// Call-site RIP that invoked the current function.
    call_site: u64 = 0,
    /// Guest instruction count spent in the current function.
    instruction_count: u64 = 0,
    /// Small call stack (depth ≤ 4) to restore function tracking on ret.
    saved_entry: [4]u64 = .{0} ** 4,
    saved_count: [4]u64 = .{0} ** 4,
    saved_call_site: [4]u64 = .{0} ** 4,
    /// Set when a hot function is detected.
    hot_function_rip: u64 = 0,
    /// Step counter at which the hot function was first detected.
    detected_at_step: u64 = 0,
    /// Whether we have reported the initial diagnostic entry.
    initial_report_done: bool = false,
    /// Throttle for periodic progress reports.
    progress_log_counter: u32 = 0,
    /// Cached SHA1 arguments from onProcessBytesEntry or logSha1EntryCall.
    /// System V x86_64: RDI=this, RSI=data, RDX=length.
    sha1_this_ptr: u64 = 0,
    sha1_data_ptr: u64 = 0,
    sha1_byte_len: u64 = 0,
    /// Last-sampled SHA1 object state for progress tracking.
    last_data_ptr: u64 = 0,
    last_block_index: u32 = 0,
    last_byte_count: u64 = 0,
    /// Cumulative blocks consumed between progress samples.
    blocks_consumed: u64 = 0,

    // --- Enhanced processBytes entry tracking ---
    /// How many times sha1::SHA1::processBytes has been entered.
    process_bytes_entry_count: u64 = 0,
    /// Data pointer from the most recent processBytes entry.
    pb_data_ptr: u64 = 0,
    /// Byte length from the most recent processBytes entry.
    pb_byte_len: u64 = 0,
    /// Previous processBytes data ptr for repeat detection.
    prev_pb_data_ptr: u64 = 0,
    /// Previous processBytes byte len for repeat detection.
    prev_pb_byte_len: u64 = 0,
    /// How many times the same (data_ptr, length) pair has been seen.
    pb_repeat_count: u64 = 0,
    /// Step when the first repeat was detected.
    pb_repeat_first_step: u64 = 0,
    /// Whether a repeated-buffer scenario has been diagnosed.
    pb_repeat_detected: bool = false,

    pub const HOT_THRESHOLD: u64 = 1_000_000;
    pub const PROGRESS_LOG_INTERVAL: u32 = 100;

    const U32_SIZE: usize = 4;
    const U64_SIZE: usize = 8;

    /// Resets all tracking state back to defaults.
    pub fn reset(self: *@This()) void {
        self.entry_rip = 0;
        self.call_site = 0;
        self.instruction_count = 0;
        self.depth = 0;
        self.hot_function_rip = 0;
        self.detected_at_step = 0;
        self.initial_report_done = false;
        self.progress_log_counter = 0;
        self.sha1_this_ptr = 0;
        self.sha1_data_ptr = 0;
        self.sha1_byte_len = 0;
        self.last_data_ptr = 0;
        self.last_block_index = 0;
        self.last_byte_count = 0;
        self.blocks_consumed = 0;
        self.process_bytes_entry_count = 0;
        self.pb_data_ptr = 0;
        self.pb_byte_len = 0;
        self.prev_pb_data_ptr = 0;
        self.prev_pb_byte_len = 0;
        self.pb_repeat_count = 0;
        self.pb_repeat_first_step = 0;
        self.pb_repeat_detected = false;
    }

    /// Called from call handler when target matches sha1_process_bytes.
    /// Captures processBytes arguments (System V: RDI=this, RSI=data, RDX=len).
    pub fn onProcessBytesEntry(self: *@This(), ctx: Context) void {
        self.process_bytes_entry_count += 1;
        const this_ptr = ctx.rdi;
        const data_ptr = ctx.rsi;
        const byte_len = ctx.rdx;
        self.pb_data_ptr = data_ptr;
        self.pb_byte_len = byte_len;

        // Detect repeated call with the same (data, length) pair
        if (data_ptr == self.prev_pb_data_ptr and byte_len == self.prev_pb_byte_len) {
            self.pb_repeat_count += 1;
            if (self.pb_repeat_count == 1) {
                self.pb_repeat_first_step = ctx.executed_steps;
            }
            if (!self.pb_repeat_detected and self.pb_repeat_count >= 3) {
                self.pb_repeat_detected = true;
                logRepeatWarning(ctx, data_ptr, byte_len, self.pb_repeat_count, ctx.executed_steps);
            }
        } else {
            self.prev_pb_data_ptr = data_ptr;
            self.prev_pb_byte_len = byte_len;
        }

        // Update the hot-function cache so logSha1Progress uses correct args
        self.sha1_this_ptr = this_ptr;
        self.sha1_data_ptr = data_ptr;
        self.sha1_byte_len = byte_len;
        self.last_data_ptr = data_ptr;

        // TinySHA1 object layout in this Xenia build:
        // buffered-byte count at +0x60=96, total byte count at +0x68=104.
        var block_index: u32 = 0;
        var byte_count: u64 = 0;
        if (ctx.readGuestMemory(ctx.opaque_ptr, this_ptr + 96, U32_SIZE)) |idx_bytes| {
            block_index = std.mem.readInt(u32, idx_bytes[0..U32_SIZE], .little);
        }
        if (ctx.readGuestMemory(ctx.opaque_ptr, this_ptr + 104, U64_SIZE)) |cnt_bytes| {
            byte_count = std.mem.readInt(u64, cnt_bytes[0..U64_SIZE], .little);
        }

        logProcessBytesEntry(ctx, ctx.executed_steps, this_ptr, data_ptr, byte_len, block_index, byte_count);
    }

    /// Called when a hot SHA1 function is detected (> HOT_THRESHOLD instructions).
    /// Logs entry details including calling convention registers and SHA1 object state.
    pub fn logSha1EntryCall(self: *@This(), ctx: Context) void {
        // Capture System V x86_64 calling convention args at function entry
        self.sha1_this_ptr = ctx.rdi;
        self.sha1_data_ptr = ctx.rsi;
        self.sha1_byte_len = ctx.rdx;
        self.last_data_ptr = self.sha1_data_ptr;
        self.sha1_byte_len = ctx.rdx;

        // Read TinySHA1 buffered-byte and total-byte counters.
        if (ctx.readGuestMemory(ctx.opaque_ptr, self.sha1_this_ptr + 96, U32_SIZE)) |idx_bytes| {
            self.last_block_index = std.mem.readInt(u32, idx_bytes[0..U32_SIZE], .little);
        }
        if (ctx.readGuestMemory(ctx.opaque_ptr, self.sha1_this_ptr + 104, U64_SIZE)) |cnt_bytes| {
            self.last_byte_count = std.mem.readInt(u64, cnt_bytes[0..U64_SIZE], .little);
        }

        const symbol = ctx.nearestSymbolName(ctx.opaque_ptr, self.entry_rip);
        const caller = ctx.nearestSymbolName(ctx.opaque_ptr, self.call_site);

        logEntryCall(
            ctx,
            self.entry_rip,
            self.call_site,
            symbol,
            caller,
            self.sha1_this_ptr,
            self.sha1_data_ptr,
            self.sha1_byte_len,
            self.last_block_index,
            self.last_byte_count,
            ctx.active_guest_thread,
            ctx.executed_steps,
        );
    }

    /// Periodic progress logging for an already-hot SHA1 function.
    /// Reads the SHA1 object state from guest memory and reports byte/block progress.
    pub fn logSha1Progress(self: *@This(), ctx: Context) void {
        // Read current SHA1 object state from guest memory
        var current_block_index: u32 = self.last_block_index;
        var current_byte_count: u64 = self.last_byte_count;
        if (ctx.readGuestMemory(ctx.opaque_ptr, self.sha1_this_ptr + 96, U32_SIZE)) |idx_bytes| {
            current_block_index = std.mem.readInt(u32, idx_bytes[0..U32_SIZE], .little);
        }
        if (ctx.readGuestMemory(ctx.opaque_ptr, self.sha1_this_ptr + 104, U64_SIZE)) |cnt_bytes| {
            current_byte_count = std.mem.readInt(u64, cnt_bytes[0..U64_SIZE], .little);
        }
        const delta_bytes = current_byte_count -| self.last_byte_count;
        const bytes_remaining = self.sha1_byte_len -| current_byte_count;
        const blocks_delta = (current_block_index -| self.last_block_index);

        logProgress(
            ctx,
            ctx.executed_steps,
            ctx.active_guest_thread,
            self.sha1_data_ptr + current_byte_count,
            delta_bytes,
            bytes_remaining,
            current_block_index,
            current_byte_count,
            blocks_delta,
        );

        // Check for stall: same 64-byte block being processed repeatedly?
        if (current_block_index == self.last_block_index and delta_bytes > 0) {
            logStallWarning(ctx, current_block_index, ctx.executed_steps);
        }
        // Check for no-progress stall: byte_count not advancing at all
        if (current_byte_count == self.last_byte_count and current_block_index == self.last_block_index) {
            logNoProgressWarning(ctx, current_byte_count, current_block_index, ctx.executed_steps);
        }
    }
};

/// Symbol information returned by nearestSymbolName callback.
pub const Sha1SymbolInfo = struct {
    name: []const u8,
    offset: u64,
};

/// Context for Sha1Tracer methods. Groups register state at function entry
/// with callbacks for memory/symbol/log access.
pub const Context = struct {
    /// System V calling convention register state at entry.
    rdi: u64 = 0,
    rsi: u64 = 0,
    rdx: u64 = 0,
    /// Current execution context.
    active_guest_thread: u64 = 0,
    executed_steps: u64 = 0,

    /// Callbacks for dynamic operations.
    readGuestMemory: *const fn (ctx: *anyopaque, addr: u64, size: usize) ?[]const u8,
    nearestSymbolName: *const fn (ctx: *anyopaque, addr: u64) ?Sha1SymbolInfo,
    logLine: *const fn (ctx: *anyopaque, line: []const u8) void,
    /// Opaque context pointer passed to all callbacks.
    opaque_ptr: *anyopaque,
};

// --- Private logging helpers ---

fn logRepeatWarning(ctx: Context, data_ptr: u64, byte_len: u64, repeat_count: u64, step: u64) void {
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 WARNING: processBytes called with SAME buffer repeatedly! data=0x{x} length={d} repeat_count={d} step={d}",
        .{ data_ptr, byte_len, repeat_count, step },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

fn logProcessBytesEntry(ctx: Context, step: u64, this_ptr: u64, data_ptr: u64, byte_len: u64, block_index: u32, byte_count: u64) void {
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 processBytes entry: step={d} this=0x{x} data=0x{x} length={d} block={d} byte_count={d}",
        .{ step, this_ptr, data_ptr, byte_len, block_index, byte_count },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

fn logEntryCall(
    ctx: Context,
    entry_rip: u64,
    call_site: u64,
    symbol: ?Sha1SymbolInfo,
    caller: ?Sha1SymbolInfo,
    this_ptr: u64,
    data_ptr: u64,
    byte_len: u64,
    block_index: u32,
    byte_count: u64,
    thread: u64,
    step: u64,
) void {
    const sym_name = if (symbol) |s| s.name else "<unknown>";
    const caller_name = if (caller) |c| c.name else "<unknown>";
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 entry: function_rip=0x{x} ({s}) caller_rip=0x{x} ({s}) this=0x{x} data=0x{x} length={d} block_index={d} byte_count={d} thread=0x{x} step={d}",
        .{ entry_rip, sym_name, call_site, caller_name, this_ptr, data_ptr, byte_len, block_index, byte_count, thread, step },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

fn logProgress(
    ctx: Context,
    step: u64,
    thread: u64,
    next_data_ptr: u64,
    delta_bytes: u64,
    bytes_remaining: u64,
    block_index: u32,
    byte_count: u64,
    blocks_delta: u32,
) void {
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 progress: step={d} data_ptr=0x{x} delta_bytes={d} bytes_remaining={d} block_index={d} byte_count={d} new_blocks_this_sample={d} thread=0x{x}",
        .{ step, next_data_ptr, delta_bytes, bytes_remaining, block_index, byte_count, blocks_delta, thread },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

fn logStallWarning(ctx: Context, block_index: u32, step: u64) void {
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 WARNING: same 64-byte block being processed repeatedly! block_index={d} step={d}",
        .{ block_index, step },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

fn logNoProgressWarning(ctx: Context, byte_count: u64, block_index: u32, step: u64) void {
    const buf = std.fmt.allocPrint(
        std.heap.page_allocator,
        "macho-processor: SHA1 WARNING: no byte/block progress since last sample! byte_count={d} block_index={d} step={d}",
        .{ byte_count, block_index, step },
    ) catch return;
    defer std.heap.page_allocator.free(buf);
    ctx.logLine(ctx.opaque_ptr, buf);
}

test "Sha1Tracer struct layout" {
    const tracer = Sha1Tracer{};
    try std.testing.expect(tracer.enabled);
    try std.testing.expectEqual(@as(u64, 0), tracer.entry_rip);
    try std.testing.expectEqual(@as(u64, 1_000_000), Sha1Tracer.HOT_THRESHOLD);
    try std.testing.expectEqual(@as(u32, 100), Sha1Tracer.PROGRESS_LOG_INTERVAL);
}

test "Sha1Tracer.reset clears fields" {
    var tracer = Sha1Tracer{
        .entry_rip = 0x1234,
        .instruction_count = 500,
        .hot_function_rip = 0x5678,
        .detected_at_step = 1000,
        .initial_report_done = true,
        .progress_log_counter = 50,
        .process_bytes_entry_count = 10,
        .pb_repeat_detected = true,
        .pb_repeat_count = 5,
    };
    tracer.reset();
    try std.testing.expectEqual(@as(u64, 0), tracer.entry_rip);
    try std.testing.expectEqual(@as(u64, 0), tracer.instruction_count);
    try std.testing.expectEqual(@as(u64, 0), tracer.hot_function_rip);
    try std.testing.expectEqual(@as(u64, 0), tracer.detected_at_step);
    try std.testing.expect(!tracer.initial_report_done);
    try std.testing.expectEqual(@as(u32, 0), tracer.progress_log_counter);
    try std.testing.expectEqual(@as(u64, 0), tracer.process_bytes_entry_count);
    try std.testing.expect(!tracer.pb_repeat_detected);
    try std.testing.expectEqual(@as(u64, 0), tracer.pb_repeat_count);
}
