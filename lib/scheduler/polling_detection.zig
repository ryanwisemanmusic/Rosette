const std = @import("std");

/// Polling detection configuration
pub const PollingConfig = struct {
    /// Maximum RIP window size for polling detection
    max_rip_window_size: u64 = 0x200, // 512 bytes
    
    /// Maximum number of memory addresses to track for polling
    max_tracked_addresses: u8 = 4,
    
    /// Minimum iterations to classify as polling
    min_polling_iterations: u64 = 1000,
    
    /// Threshold for "no relevant stores" (steps)
    no_store_threshold: u64 = 500_000,
    
    /// Instructions retired threshold for external event
    external_event_threshold: u64 = 1_000_000,
};

/// Memory access record for polling detection
pub const MemoryAccessRecord = struct {
    address: u64 = 0,
    value: u64 = 0,
    width: u8 = 4, // bytes
    is_write: bool = false,
    timestamp: u64 = 0,
};

/// Branch record for polling detection
pub const BranchRecord = struct {
    from_rip: u64 = 0,
    to_rip: u64 = 0,
    taken: bool = false,
    timestamp: u64 = 0,
};

/// Polling detection state for a thread
pub const PollingState = struct {
    /// Whether polling detection is active
    active: bool = false,
    
    /// RIP window (start and end addresses)
    rip_window_start: u64 = 0,
    rip_window_end: u64 = 0,
    
    /// Memory access records
    memory_accesses: [16]MemoryAccessRecord = [_]MemoryAccessRecord{.{}} ** 16,
    memory_access_count: u8 = 0,
    memory_access_index: u8 = 0,
    
    /// Branch records
    branches: [16]BranchRecord = [_]BranchRecord{.{}} ** 16,
    branch_count: u8 = 0,
    branch_index: u8 = 0,
    
    /// Number of polling iterations detected
    polling_iterations: u64 = 0,
    
    /// Step when polling detection started
    start_step: u64 = 0,
    
    /// Last observed values at tracked addresses
    last_values: [8]u64 = [_]u64{0} ** 8,
    
    /// Whether any stores have occurred during polling
    stores_occurred: bool = false,
    
    /// Whether any calls with side effects have occurred
    side_effect_calls: bool = false,
    
    /// Last step when an external event occurred
    last_external_event_step: u64 = 0,
    
    /// Instructions retired since last external event
    instructions_since_event: u64 = 0,
    
    /// Tracked memory addresses for polling
    tracked_addresses: [8]u64 = [_]u64{0} ** 8,
    tracked_address_count: u8 = 0,
    
    /// Whether this has been classified as polling
    classified_as_polling: bool = false,
    
    /// Address being polled (if classified)
    polling_address: ?u64 = null,
    
    /// Last writer thread handle (if known)
    last_writer_handle: ?u64 = null,
    
    /// Last writer RIP (if known)
    last_writer_rip: ?u64 = null,
};

/// Polling detection manager
pub const PollingDetectionManager = struct {
    /// Configuration
    config: PollingConfig = .{},
    
    /// Polling states per thread
    polling_states: std.AutoHashMap(u64, PollingState),
    
    /// Memory address to last writer mapping (simplified)
    address_writers: std.AutoHashMap(u64, u64), // address -> thread_handle
    
    /// Statistics
    total_polling_detections: u64 = 0,
    total_polling_reports: u64 = 0,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Initialize the polling detection manager
    pub fn init(allocator: std.mem.Allocator) PollingDetectionManager {
        return .{
            .polling_states = std.AutoHashMap(u64, PollingState).init(allocator),
            .address_writers = std.AutoHashMap(u64, u64).init(allocator),
            .allocator = allocator,
        };
    }
    
    /// Deinitialize the polling detection manager
    pub fn deinit(self: *PollingDetectionManager) void {
        self.polling_states.deinit();
        self.address_writers.deinit();
    }
    
    /// Start polling detection for a thread
    pub fn startDetection(
        self: *PollingDetectionManager,
        thread_handle: u64,
        current_rip: u64,
        current_step: u64,
    ) void {
        const state = self.polling_states.getOrPut(thread_handle) catch return;
        if (!state.found_existing) {
            state.value_ptr.* = .{
                .active = true,
                .rip_window_start = current_rip,
                .rip_window_end = current_rip + self.config.max_rip_window_size,
                .start_step = current_step,
                .last_external_event_step = current_step,
            };
        } else {
            // Reset state if RIP moved outside window
            if (current_rip < state.value_ptr.rip_window_start or 
                current_rip > state.value_ptr.rip_window_end) {
                state.value_ptr.* = .{
                    .active = true,
                    .rip_window_start = current_rip,
                    .rip_window_end = current_rip + self.config.max_rip_window_size,
                    .start_step = current_step,
                    .last_external_event_step = current_step,
                };
            }
        }
    }
    
    /// Record a memory access
    pub fn recordMemoryAccess(
        self: *PollingDetectionManager,
        thread_handle: u64,
        address: u64,
        value: u64,
        width: u8,
        is_write: bool,
        current_step: u64,
    ) void {
        const state = self.polling_states.getPtr(thread_handle) orelse return;
        if (!state.active) return;
        
        // Record the access
        const idx = state.memory_access_index;
        state.memory_accesses[idx] = .{
            .address = address,
            .value = value,
            .width = width,
            .is_write = is_write,
            .timestamp = current_step,
        };
        state.memory_access_index = (idx + 1) % state.memory_accesses.len;
        if (state.memory_access_count < state.memory_accesses.len) {
            state.memory_access_count += 1;
        }
        
        // Track if this is a write
        if (is_write) {
            state.stores_occurred = true;
            
            // Update address writer mapping (simplified)
            self.address_writers.put(address, thread_handle) catch {};
        }
        
        // Track address if reading
        if (!is_write) {
            // Check if already tracked
            var already_tracked = false;
            for (0..state.tracked_address_count) |i| {
                if (state.tracked_addresses[i] == address) {
                    already_tracked = true;
                    state.last_values[i] = value;
                    break;
                }
            }
            
            // Add to tracked addresses if not already tracked
            if (!already_tracked and state.tracked_address_count < state.tracked_addresses.len) {
                state.tracked_addresses[state.tracked_address_count] = address;
                state.last_values[state.tracked_address_count] = value;
                state.tracked_address_count += 1;
            }
        }
    }
    
    /// Record a branch
    pub fn recordBranch(
        self: *PollingDetectionManager,
        thread_handle: u64,
        from_rip: u64,
        to_rip: u64,
        taken: bool,
        current_step: u64,
    ) void {
        const state = self.polling_states.getPtr(thread_handle) orelse return;
        if (!state.active) return;
        
        const idx = state.branch_index;
        state.branches[idx] = .{
            .from_rip = from_rip,
            .to_rip = to_rip,
            .taken = taken,
            .timestamp = current_step,
        };
        state.branch_index = (idx + 1) % state.branches.len;
        if (state.branch_count < state.branches.len) {
            state.branch_count += 1;
        }
    }
    
    /// Record a call with potential side effects
    pub fn recordSideEffectCall(
        self: *PollingDetectionManager,
        thread_handle: u64,
        current_step: u64,
    ) void {
        const state = self.polling_states.getPtr(thread_handle) orelse return;
        if (!state.active) return;
        
        state.side_effect_calls = true;
        state.last_external_event_step = current_step;
        state.instructions_since_event = 0;
    }
    
    /// Record an external event
    pub fn recordExternalEvent(
        self: *PollingDetectionManager,
        thread_handle: u64,
        current_step: u64,
    ) void {
        const state = self.polling_states.getPtr(thread_handle) orelse return;
        if (!state.active) return;
        
        state.last_external_event_step = current_step;
        state.instructions_since_event = 0;
    }
    
    /// Update instruction count
    pub fn updateInstructionCount(
        self: *PollingDetectionManager,
        thread_handle: u64,
        instructions: u64,
    ) void {
        const state = self.polling_states.getPtr(thread_handle) orelse return;
        if (!state.active) return;
        
        state.instructions_since_event +|= instructions;
        state.polling_iterations +|= 1;
    }
    
    /// Classify if the thread is polling
    pub fn classifyPolling(
        self: *PollingDetectionManager,
        thread_handle: u64,
        current_step: u64,
        current_rip: u64,
    ) ?PollingClassification {
        _ = current_step;
        _ = current_rip;
        const state = self.polling_states.getPtr(thread_handle) orelse return null;
        if (!state.active) return null;
        
        // Check if already classified
        if (state.classified_as_polling) {
            return .{
                .is_polling = true,
                .polling_address = state.polling_address,
                .iterations = state.polling_iterations,
                .last_writer = state.last_writer_handle,
                .last_writer_rip = state.last_writer_rip,
            };
        }
        
        // Check minimum iterations
        if (state.polling_iterations < self.config.min_polling_iterations) {
            return null;
        }
        
        // Check RIP window size (should be small)
        const rip_window_size = state.rip_window_end - state.rip_window_start;
        if (rip_window_size > self.config.max_rip_window_size) {
            return null;
        }
        
        // Check number of tracked addresses (should be 1-2)
        if (state.tracked_address_count == 0 or state.tracked_address_count > 2) {
            return null;
        }
        
        // Check if stores occurred (should be none or minimal)
        if (state.stores_occurred) {
            return null;
        }
        
        // Check if side effect calls occurred (should be none)
        if (state.side_effect_calls) {
            return null;
        }
        
        // Check if values have changed (should be unchanged)
        var values_unchanged = true;
        for (0..state.tracked_address_count) |i| {
            const current_value = state.last_values[i];
            // Check recent memory accesses for this address
            for (0..@min(state.memory_access_count, 8)) |j| {
                const access_idx = if (state.memory_access_index >= j)
                    state.memory_access_index - j
                else
                    state.memory_accesses.len + state.memory_access_index - j;
                const access = state.memory_accesses[access_idx];
                if (access.address == state.tracked_addresses[i] and !access.is_write) {
                    if (access.value != current_value) {
                        values_unchanged = false;
                        break;
                    }
                }
            }
            if (!values_unchanged) break;
        }
        
        if (!values_unchanged) {
            return null;
        }
        
        // All checks passed - classify as polling
        state.classified_as_polling = true;
        state.polling_address = state.tracked_addresses[0];
        
        // Get last writer info (simplified)
        if (self.address_writers.get(state.tracked_addresses[0])) |writer_handle| {
            state.last_writer_handle = writer_handle;
            state.last_writer_rip = null; // RIP tracking removed
        }
        
        self.total_polling_detections +|= 1;
        
        return .{
            .is_polling = true,
            .polling_address = state.polling_address,
            .iterations = state.polling_iterations,
            .last_writer = state.last_writer_handle,
            .last_writer_rip = state.last_writer_rip,
        };
    }
    
    /// Clear polling state for a thread
    pub fn clearState(self: *PollingDetectionManager, thread_handle: u64) void {
        _ = self.polling_states.remove(thread_handle);
    }
    
    /// Get polling state for a thread
    pub fn getState(self: *const PollingDetectionManager, thread_handle: u64) ?*const PollingState {
        return self.polling_states.get(thread_handle);
    }
    
    /// Update last writer RIP (no-op with simplified mapping)
    pub fn updateWriterRip(
        self: *PollingDetectionManager,
        address: u64,
        rip: u64,
    ) void {
        _ = self;
        _ = address;
        _ = rip;
        // Simplified - RIP tracking removed
    }
    
    /// Log statistics
    pub fn logSummary(self: *const PollingDetectionManager) void {
        std.debug.print(
            "scheduler: polling detection: detections={d} reports={d}\n",
            .{ self.total_polling_detections, self.total_polling_reports },
        );
    }
};

/// Polling classification result
pub const PollingClassification = struct {
    is_polling: bool = false,
    polling_address: ?u64 = null,
    iterations: u64 = 0,
    last_writer: ?u64 = null,
    last_writer_rip: ?u64 = null,
};

/// Generate a diagnostic message for polling
pub fn formatPollingDiagnostic(
    classification: PollingClassification,
    thread_handle: u64,
    thread_id: u64,
    writer_state: ?struct {
        state: []const u8,
        condvar: ?u64,
        generation: ?u64,
    },
) []const u8 {
    const allocator = std.heap.page_allocator;
    var message = std.ArrayList(u8).init(allocator);
    defer message.deinit();
    
    message.writer().print(
        "Thread {d} (handle=0x{x}) polling 0x{x} for {d} iterations.\n",
        .{ thread_id, thread_handle, classification.polling_address orelse 0, classification.iterations }
    ) catch return "";
    
    if (classification.last_writer) |writer_handle| {
        message.writer().print(
            "Last writer: thread handle=0x{x}",
            .{ writer_handle }
        ) catch {};
        
        if (classification.last_writer_rip) |writer_rip| {
            message.writer().print(" at RIP=0x{x}", .{ writer_rip }) catch {};
        }
        message.writer().print("\n", .{}) catch {};
        
        if (writer_state) |ws| {
            message.writer().print(
                "Thread 0x{x} is {s}",
                .{ writer_handle, ws.state }
            ) catch {};
            
            if (ws.condvar) |condvar| {
                message.writer().print(" on condvar 0x{x}", .{ condvar }) catch {};
            }
            
            if (ws.generation) |gen| {
                message.writer().print(" generation {d}", .{ gen }) catch {};
            }
            
            message.writer().print("\n", .{}) catch {};
        }
    }
    
    return message.toOwnedSlice() catch "";
}

test "polling detection basic operations" {
    const allocator = std.testing.allocator;
    var manager = PollingDetectionManager.init(allocator);
    defer manager.deinit();
    
    // Start detection
    manager.startDetection(0x1000, 0x2000, 1000);
    
    // Record memory accesses
    manager.recordMemoryAccess(0x1000, 0x5000, 0x1234, 4, false, 1001);
    manager.recordMemoryAccess(0x1000, 0x5000, 0x1234, 4, false, 1002);
    
    // Update instruction count
    manager.updateInstructionCount(0x1000, 1000);
    
    // Get state
    const state = manager.getState(0x1000);
    try std.testing.expect(state != null);
    try std.testing.expect(state.?.active);
    try std.testing.expectEqual(@as(u8, 1), state.?.tracked_address_count);
    
    // Clear state
    manager.clearState(0x1000);
    const cleared_state = manager.getState(0x1000);
    try std.testing.expect(cleared_state == null);
}