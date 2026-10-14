//! Frozen pre-pass scanning pool; CPU test/benchmark reference only.
pub fn Pool(comptime pool_capacity: usize) type {
    return struct {
        // Retain enough continuation buffers for the bounded in-flight queue,
        // even if every outstanding guest recording reaches its full chain size.
        pub const capacity = pool_capacity;
        pub const Entry = struct {
            handle: u64 = 0,
            in_use: bool = false,
            /// A driver operation left this command buffer's recording state
            /// uncertain. Keep its handle for command-pool destruction, but never
            /// hand it to another recording.
            poisoned: bool = false,
            /// Submission serial that must complete before reuse; 0 = none.
            release_after: u64 = 0,
            last_submit: u64 = 0,
        };

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: usize = 0,
        allocated: u64 = 0,
        reuses: u64 = 0,
        exhausted: u64 = 0,
        poisoned_count: u64 = 0,

        /// A free chunk whose last submission is complete, or null when the
        /// caller must allocate (or give up when the pool is full).
        pub fn acquire(self: *@This(), completed_serial: u64) ?u64 {
            for (self.entries[0..self.count]) |*entry| {
                if (entry.poisoned or entry.in_use or entry.release_after > completed_serial) continue;
                entry.in_use = true;
                entry.release_after = 0;
                entry.last_submit = 0;
                self.reuses +|= 1;
                return entry.handle;
            }
            return null;
        }

        pub fn canGrow(self: *const @This()) bool {
            return self.count < capacity;
        }

        pub fn add(self: *@This(), handle: u64) bool {
            if (self.count == capacity) {
                self.exhausted +|= 1;
                return false;
            }
            self.entries[self.count] = .{ .handle = handle, .in_use = true };
            self.count += 1;
            self.allocated +|= 1;
            return true;
        }

        pub fn noteSubmitted(self: *@This(), handle: u64, serial: u64) void {
            if (self.find(handle)) |entry| entry.last_submit = serial;
        }

        pub fn release(self: *@This(), handle: u64) void {
            const entry = self.find(handle) orelse return;
            if (entry.poisoned) return;
            entry.in_use = false;
            entry.release_after = entry.last_submit;
        }

        /// Quarantine a handle whose driver-side recording state is uncertain.
        /// Keeping it in the pool lets vkDestroyCommandPool reclaim it at teardown
        /// without risking a reset/re-record on a potentially invalid buffer.
        pub fn discard(self: *@This(), handle: u64) void {
            const entry = self.find(handle) orelse return;
            if (entry.poisoned) return;
            entry.poisoned = true;
            entry.in_use = false;
            self.poisoned_count +|= 1;
        }

        fn find(self: *@This(), handle: u64) ?*Entry {
            for (self.entries[0..self.count]) |*entry| {
                if (entry.handle == handle) return entry;
            }
            return null;
        }
    };
}
