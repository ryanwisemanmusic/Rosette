const std = @import("std");

/// Operand width for memory operations
pub const OperandWidth = enum(u8) {
    u8 = 1,
    u16 = 2,
    u32 = 4,
    u64 = 8,
};

/// Spin wait configuration
pub const SpinConfig = struct {
    /// Maximum spin iterations before yielding
    max_spin_iterations: u64 = 1000,
    
    /// Maximum spin iterations before parking
    max_spin_before_park: u64 = 10000,
    
    /// Spin detection threshold (steps per second)
    spin_detection_threshold: u64 = 5_000_000,
    
    /// Address watch timeout (steps)
    watch_timeout: u64 = 1_000_000,
};

/// Memory address watch entry
pub const AddressWatch = struct {
    /// Thread handle waiting on this address
    thread_handle: u64 = 0,
    
    /// Memory address being watched
    address: u64 = 0,
    
    /// Expected value at the address
    expected_value: u64 = 0,
    
    /// Width of the memory operation
    width: OperandWidth = .u32,
    
    /// Whether the watch is active
    active: bool = false,
    
    /// Step when the watch was established
    watch_step: u64 = 0,
    
    /// Optional deadline for the watch
    deadline: ?u64 = null,
    
    /// Number of times this watch has been re-armed
    rearm_count: u64 = 0,
};

/// Spin detection state for a thread
pub const SpinState = struct {
    /// Whether spin detection is active
    active: bool = false,
    
    /// RIP window for spin detection (small range of addresses)
    rip_window_start: u64 = 0,
    rip_window_end: u64 = 0,
    
    /// Memory addresses being read in the spin loop
    read_addresses: [8]u64 = [_]u64{0} ** 8,
    read_address_count: u8 = 0,
    
    /// Values observed at the read addresses
    observed_values: [8]u64 = [_]u64{0} ** 8,
    
    /// Number of spin iterations detected
    spin_iterations: u64 = 0,
    
    /// Step when spin detection started
    spin_start_step: u64 = 0,
    
    /// Whether the thread has yielded during spin detection
    has_yielded: bool = false,
    
    /// Whether memory has been modified during spin detection
    memory_modified: bool = false,
};

/// Spin parking manager
pub const SpinParkingManager = struct {
    const MAX_WATCHES = 256;
    
    /// Configuration
    config: SpinConfig = .{},
    
    /// Address watches
    watches: [MAX_WATCHES]AddressWatch = [_]AddressWatch{.{}} ** MAX_WATCHES,
    
    /// Spin states per thread (indexed by handle)
    spin_states: std.AutoHashMap(u64, SpinState),
    
    /// Statistics
    total_spin_detections: u64 = 0,
    total_parks: u64 = 0,
    total_wakeups: u64 = 0,
    total_yields_from_spin: u64 = 0,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Initialize the spin parking manager
    pub fn init(allocator: std.mem.Allocator) SpinParkingManager {
        return .{
            .spin_states = std.AutoHashMap(u64, SpinState).init(allocator),
            .allocator = allocator,
        };
    }
    
    /// Deinitialize the spin parking manager
    pub fn deinit(self: *SpinParkingManager) void {
        self.spin_states.deinit();
    }
    
    /// Detect spin loop for a thread
    pub fn detectSpinLoop(
        self: *SpinParkingManager,
        thread_handle: u64,
        current_rip: u64,
        current_step: u64,
        steps_per_second: u64,
    ) bool {
        // Check if spin rate exceeds threshold
        if (steps_per_second < self.config.spin_detection_threshold) {
            return false;
        }
        
        // Get or create spin state for this thread
        const spin_state = self.spin_states.getOrPut(thread_handle) catch return false;
        if (!spin_state.found_existing) {
            spin_state.value_ptr.* = .{
                .active = true,
                .rip_window_start = current_rip,
                .rip_window_end = current_rip + 0x100, // 256-byte window
                .spin_start_step = current_step,
            };
            self.total_spin_detections +|= 1;
            return true;
        }
        
        // Check if RIP is within the spin window
        if (current_rip < spin_state.value_ptr.rip_window_start or 
            current_rip > spin_state.value_ptr.rip_window_end) {
            // RIP moved outside window, reset spin detection
            spin_state.value_ptr.* = .{
                .active = true,
                .rip_window_start = current_rip,
                .rip_window_end = current_rip + 0x100,
                .spin_start_step = current_step,
            };
            return false;
        }
        
        // Increment spin iteration count
        spin_state.value_ptr.spin_iterations +|= 1;
        
        // Check if we should yield or park
        if (!spin_state.value_ptr.has_yielded and 
            spin_state.value_ptr.spin_iterations >= self.config.max_spin_iterations) {
            spin_state.value_ptr.has_yielded = true;
            self.total_yields_from_spin +|= 1;
            return true; // Signal to yield
        }
        
        if (spin_state.value_ptr.spin_iterations >= self.config.max_spin_before_park) {
            // Should park - caller needs to set up address watch
            return true;
        }
        
        return false;
    }
    
    /// Record a memory read during spin detection
    pub fn recordMemoryRead(
        self: *SpinParkingManager,
        thread_handle: u64,
        address: u64,
        value: u64,
    ) void {
        const spin_state = self.spin_states.getPtr(thread_handle) orelse return;
        if (!spin_state.active) return;
        
        // Add to read addresses if not already tracked
        for (0..spin_state.read_address_count) |i| {
            if (spin_state.read_addresses[i] == address) {
                // Update observed value
                spin_state.observed_values[i] = value;
                return;
            }
        }
        
        // Add new address if space available
        if (spin_state.read_address_count < spin_state.read_addresses.len) {
            spin_state.read_addresses[spin_state.read_address_count] = address;
            spin_state.observed_values[spin_state.read_address_count] = value;
            spin_state.read_address_count += 1;
        }
    }
    
    /// Record a memory write during spin detection
    pub fn recordMemoryWrite(
        self: *SpinParkingManager,
        thread_handle: u64,
        address: u64,
    ) void {
        const spin_state = self.spin_states.getPtr(thread_handle) orelse return;
        if (!spin_state.active) return;
        
        // Check if this write overlaps any watched address
        for (0..spin_state.read_address_count) |i| {
            if (spin_state.read_addresses[i] == address) {
                spin_state.memory_modified = true;
                return;
            }
        }
    }
    
    /// Set up an address watch for a thread
    pub fn setupAddressWatch(
        self: *SpinParkingManager,
        thread_handle: u64,
        address: u64,
        expected_value: u64,
        width: OperandWidth,
        deadline: ?u64,
        current_step: u64,
    ) !void {
        // Find free watch slot
        for (&self.watches) |*watch| {
            if (!watch.active) {
                watch.* = .{
                    .thread_handle = thread_handle,
                    .address = address,
                    .expected_value = expected_value,
                    .width = width,
                    .active = true,
                    .watch_step = current_step,
                    .deadline = deadline,
                };
                self.total_parks +|= 1;
                return;
            }
        }
        return error.WatchTableFull;
    }
    
    /// Check if a memory write triggers any address watches
    pub fn checkMemoryWrite(
        self: *SpinParkingManager,
        address: u64,
        new_value: u64,
        current_step: u64,
    ) ?u64 {
        _ = current_step;
        
        for (&self.watches) |*watch| {
            if (!watch.active) continue;
            
            // Check if address overlaps (simple equality for now)
            if (watch.address == address) {
                // Check if value changed
                const watch_value = switch (watch.width) {
                    .u8 => @as(u64, @truncate(watch.expected_value)),
                    .u16 => @as(u64, @truncate(watch.expected_value)),
                    .u32 => @as(u64, @truncate(watch.expected_value)),
                    .u64 => watch.expected_value,
                };
                
                const new_watch_value = switch (watch.width) {
                    .u8 => @as(u64, @truncate(new_value)),
                    .u16 => @as(u64, @truncate(new_value)),
                    .u32 => @as(u64, @truncate(new_value)),
                    .u64 => new_value,
                };
                
                if (new_watch_value != watch_value) {
                    // Value changed, wake the thread
                    const thread_handle = watch.thread_handle;
                    watch.active = false;
                    self.total_wakeups +|= 1;
                    return thread_handle;
                }
            }
        }
        
        return null;
    }
    
    /// Check for expired watches and wake threads
    pub fn checkExpiredWatches(self: *SpinParkingManager, current_step: u64) ?[]const u64 {
        var expired_threads = std.ArrayList(u64).init(self.allocator);
        defer {
            if (expired_threads.items.len == 0) {
                expired_threads.deinit();
            }
        }
        
        for (&self.watches) |*watch| {
            if (!watch.active) continue;
            
            const expired = if (watch.deadline) |deadline|
                current_step >= deadline
            else
                current_step -| watch.watch_step >= self.config.watch_timeout;
            
            if (expired) {
                expired_threads.append(watch.thread_handle) catch {};
                watch.active = false;
            }
        }
        
        if (expired_threads.items.len == 0) {
            return null;
        }
        
        return expired_threads.toOwnedSlice();
    }
    
    /// Clear spin state for a thread
    pub fn clearSpinState(self: *SpinParkingManager, thread_handle: u64) void {
        _ = self.spin_states.remove(thread_handle);
        
        // Clear any watches for this thread
        for (&self.watches) |*watch| {
            if (watch.active and watch.thread_handle == thread_handle) {
                watch.active = false;
            }
        }
    }
    
    /// Get spin state for a thread
    pub fn getSpinState(self: *const SpinParkingManager, thread_handle: u64) ?SpinState {
        return self.spin_states.get(thread_handle);
    }
    
    /// Get recommended polling address for a thread
    pub fn getPollingAddress(self: *const SpinParkingManager, thread_handle: u64) ?struct {
        address: u64,
        expected_value: u64,
        width: OperandWidth,
    } {
        const spin_state = self.spin_states.get(thread_handle) orelse return null;
        if (!spin_state.active or spin_state.read_address_count == 0) return null;
        
        // Return the most frequently read address
        return .{
            .address = spin_state.read_addresses[0],
            .expected_value = spin_state.observed_values[0],
            .width = .u32, // Default to 32-bit
        };
    }
    
    /// Log statistics
    pub fn logSummary(self: *const SpinParkingManager) void {
        std.debug.print(
            "scheduler: spin parking: detections={d} parks={d} wakeups={d} yields={d}\n",
            .{ self.total_spin_detections, self.total_parks, self.total_wakeups, self.total_yields_from_spin },
        );
    }
};

test "spin parking basic operations" {
    const allocator = std.testing.allocator;
    var manager = SpinParkingManager.init(allocator);
    defer manager.deinit();
    
    // Test spin detection
    const detected = manager.detectSpinLoop(0x1000, 0x2000, 1000, 6_000_000);
    try std.testing.expect(detected);
    
    const spin_state = manager.getSpinState(0x1000);
    try std.testing.expect(spin_state != null);
    try std.testing.expect(spin_state.?.active);
    
    // Test memory read recording
    manager.recordMemoryRead(0x1000, 0x5000, 0x1234);
    const updated_state = manager.getSpinState(0x1000);
    try std.testing.expect(updated_state.?.read_address_count == 1);
    try std.testing.expectEqual(@as(u64, 0x5000), updated_state.?.read_addresses[0]);
    
    // Test address watch setup
    try manager.setupAddressWatch(0x1000, 0x5000, 0x1234, .u32, null, 2000);
    
    // Test memory write triggering watch
    const woke_thread = manager.checkMemoryWrite(0x5000, 0x5678, 3000);
    try std.testing.expect(woke_thread != null);
    try std.testing.expectEqual(@as(u64, 0x1000), woke_thread.?);
    
    // Test spin state clearing
    manager.clearSpinState(0x1000);
    const cleared_state = manager.getSpinState(0x1000);
    try std.testing.expect(cleared_state == null);
}