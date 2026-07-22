const std = @import("std");

/// Wait-for graph node types
pub const WaitNodeType = enum {
    /// Thread waiting on something
    thread,
    /// Mutex owned by a thread
    mutex,
    /// Condition variable with waiters
    condvar,
    /// Event being signaled
    event,
    /// Timer callback
    timer,
    /// Spin waiter watching memory
    spin_waiter,
    /// Memory address being watched
    memory_address,
};

/// Wait-for graph node
pub const WaitNode = struct {
    /// Node type
    node_type: WaitNodeType = .thread,
    
    /// Node identifier (thread handle, mutex address, etc.)
    id: u64 = 0,
    
    /// Associated data (e.g., thread state, mutex owner)
    data: u64 = 0,
    
    /// Outgoing edges (dependencies)
    edges: [8]u64 = [_]u64{0} ** 8,
    edge_count: u8 = 0,
    
    /// Whether this node is active
    active: bool = false,
};

/// Wait-for graph
pub const WaitForGraph = struct {
    const MAX_NODES = 512;
    
    /// Graph nodes
    nodes: [MAX_NODES]WaitNode = [_]WaitNode{.{}} ** MAX_NODES,
    
    /// Statistics
    total_cycles_detected: u64 = 0,
    total_deadlocks: u64 = 0,
    total_livelocks: u64 = 0,
    
    /// Allocator
    allocator: std.mem.Allocator,
    
    /// Initialize the wait-for graph
    pub fn init(allocator: std.mem.Allocator) WaitForGraph {
        return .{
            .allocator = allocator,
        };
    }
    
    /// Add or update a node
    pub fn addNode(
        self: *WaitForGraph,
        node_type: WaitNodeType,
        id: u64,
        data: u64,
    ) !*WaitNode {
        // Find existing node or free slot
        for (&self.nodes) |*node| {
            if (node.active and node.node_type == node_type and node.id == id) {
                node.data = data;
                return node;
            }
            if (!node.active) {
                node.* = .{
                    .node_type = node_type,
                    .id = id,
                    .data = data,
                    .active = true,
                };
                return node;
            }
        }
        return error.GraphFull;
    }
    
    /// Add an edge between nodes
    pub fn addEdge(self: *WaitForGraph, from_id: u64, to_id: u64) !void {
        const from_node = self.findNode(from_id) orelse return error.NodeNotFound;
        if (from_node.edge_count >= from_node.edges.len) return error.EdgeLimitExceeded;
        
        // Check if edge already exists
        for (0..from_node.edge_count) |i| {
            if (from_node.edges[i] == to_id) return;
        }
        
        from_node.edges[from_node.edge_count] = to_id;
        from_node.edge_count += 1;
    }
    
    /// Find a node by ID
    pub fn findNode(self: *const WaitForGraph, id: u64) ?*WaitNode {
        for (&self.nodes) |*node| {
            if (node.active and node.id == id) return node;
        }
        return null;
    }
    
    /// Remove a node
    pub fn removeNode(self: *WaitForGraph, id: u64) void {
        for (&self.nodes) |*node| {
            if (node.active and node.id == id) {
                node.active = false;
                node.edge_count = 0;
                @memset(&node.edges, 0);
                return;
            }
        }
        
        // Remove edges pointing to this node
        for (&self.nodes) |*node| {
            if (!node.active) continue;
            var new_count: u8 = 0;
            var i: u8 = 0;
            while (i < node.edge_count) {
                if (node.edges[i] != id) {
                    node.edges[new_count] = node.edges[i];
                    new_count += 1;
                }
                i += 1;
            }
            node.edge_count = new_count;
        }
    }
    
    /// Detect cycles in the graph
    pub fn detectCycles(self: *const WaitForGraph) ![]const []const u64 {
        var cycles = std.ArrayList([]const u64).init(self.allocator);
        errdefer {
            for (cycles.items) |cycle| {
                self.allocator.free(cycle);
            }
            cycles.deinit();
        }
        
        var visited = std.AutoHashMap(u64, bool).init(self.allocator);
        defer visited.deinit();
        
        var recursion_stack = std.ArrayList(u64).init(self.allocator);
        defer recursion_stack.deinit();
        
        for (&self.nodes) |*node| {
            if (!node.active) continue;
            if (visited.get(node.id)) |v| if (v) continue;
            
            visited.put(node.id, false) catch {};
            recursion_stack.clearRetainingCapacity();
            
            if (try self.detectCycleDFS(node.id, &visited, &recursion_stack)) {
                // Found a cycle - add to results
                const cycle = try self.allocator.dupe(u64, recursion_stack.items);
                try cycles.append(cycle);
            }
        }
        
        if (cycles.items.len == 0) {
            cycles.deinit();
            return null;
        }
        
        return cycles.toOwnedSlice();
    }
    
    /// DFS cycle detection
    fn detectCycleDFS(
        self: *const WaitForGraph,
        node_id: u64,
        visited: *std.AutoHashMap(u64, bool),
        recursion_stack: *std.ArrayList(u64),
    ) !bool {
        visited.put(node_id, true) catch {};
        try recursion_stack.append(node_id);
        
        const node = self.findNode(node_id) orelse return false;
        
        for (0..node.edge_count) |i| {
            const neighbor_id = node.edges[i];
            
            const neighbor_visited = visited.get(neighbor_id) orelse false;
            if (!neighbor_visited) {
                if (try self.detectCycleDFS(neighbor_id, visited, recursion_stack)) {
                    return true;
                }
            } else if (recursion_stack.contains(neighbor_id)) {
                // Found cycle
                return true;
            }
        }
        
        _ = recursion_stack.pop();
        return false;
    }
    
    /// Classify the type of blocking
    pub fn classifyBlocking(
        self: *const WaitForGraph,
        thread_handle: u64,
    ) ?BlockingClassification {
        const thread_node = self.findNode(thread_handle) orelse return null;
        
        // Check if thread is in a cycle
        var in_cycle = false;
        const cycles = self.detectCycles() catch return null;
        defer {
            if (cycles) |c| {
                for (c) |cycle| {
                    self.allocator.free(cycle);
                }
                self.allocator.free(c);
            }
        }
        
        if (cycles) |c| {
            for (c) |cycle| {
                for (cycle) |node_id| {
                    if (node_id == thread_handle) {
                        in_cycle = true;
                        break;
                    }
                }
                if (in_cycle) break;
            }
        }
        
        if (in_cycle) {
            return .{
                .type = .deadlock,
                .cycle = true,
                .description = "Thread is part of a dependency cycle",
            };
        }
        
        // Check if thread is waiting on a condition variable
        for (0..thread_node.edge_count) |i| {
            const target_id = thread_node.edges[i];
            const target_node = self.findNode(target_id) orelse continue;
            
            if (target_node.node_type == .condvar) {
                return .{
                    .type = .waiting_condvar,
                    .cycle = false,
                    .description = "Thread waiting on condition variable",
                    .condvar = target_id,
                };
            }
            
            if (target_node.node_type == .mutex) {
                return .{
                    .type = .waiting_mutex,
                    .cycle = false,
                    .description = "Thread waiting for mutex",
                    .mutex = target_id,
                };
            }
            
            if (target_node.node_type == .spin_waiter) {
                return .{
                    .type = .spin_waiting,
                    .cycle = false,
                    .description = "Thread spin-waiting on memory address",
                    .address = target_id,
                };
            }
        }
        
        return .{
            .type = .unknown,
            .cycle = false,
            .description = "Thread state unknown",
        };
    }
    
    /// Generate a diagnostic dump
    pub fn generateDiagnosticDump(
        self: *const WaitForGraph,
        thread_states: ?std.AutoHashMap(u64, ThreadStateInfo),
    ) ![]const u8 {
        var message = std.ArrayList(u8).init(self.allocator);
        errdefer message.deinit();
        
        try message.writer().print("Wait-for Graph Diagnostic:\n", .{});
        
        for (&self.nodes) |*node| {
            if (!node.active) continue;
            
            const type_str = switch (node.node_type) {
                .thread => "THREAD",
                .mutex => "MUTEX",
                .condvar => "CONDVAR",
                .event => "EVENT",
                .timer => "TIMER",
                .spin_waiter => "SPIN_WAIT",
                .memory_address => "MEMORY",
            };
            
            try message.writer().print(
                "  {s} 0x{x} ->",
                .{ type_str, node.id }
            );
            
            for (0..node.edge_count) |i| {
                try message.writer().print(" 0x{x}", .{ node.edges[i] });
            }
            
            // Add thread state info if available
            if (node.node_type == .thread and thread_states != null) {
                if (thread_states.?.get(node.id)) |state| {
                    try message.writer().print(" ({s})", .{ state.state_str });
                }
            }
            
            try message.writer().print("\n", .{});
        }
        
        // Detect and report cycles
        const cycles = self.detectCycles() catch null;
        defer {
            if (cycles) |c| {
                for (c) |cycle| {
                    self.allocator.free(cycle);
                }
                self.allocator.free(c);
            }
        }
        
        if (cycles) |c| {
            try message.writer().print("\nDetected {d} cycles:\n", .{ c.len });
            for (c, 0..) |cycle, i| {
                try message.writer().print("  Cycle {d}: ", .{ i });
                for (cycle, 0..) |node_id, j| {
                    try message.writer().print("0x{x}", .{ node_id });
                    if (j < cycle.len - 1) {
                        try message.writer().print(" -> ", .{});
                    }
                }
                try message.writer().print("\n", .{});
            }
        }
        
        return message.toOwnedSlice();
    }
    
    /// Clear the graph
    pub fn clear(self: *WaitForGraph) void {
        for (&self.nodes) |*node| {
            node.active = false;
            node.edge_count = 0;
            @memset(&node.edges, 0);
        }
    }
    
    /// Log statistics
    pub fn logSummary(self: *const WaitForGraph) void {
        var active_count: usize = 0;
        for (&self.nodes) |*node| {
            if (node.active) active_count += 1;
        }
        
        std.debug.print(
            "scheduler: wait-for graph: nodes={d} cycles={d} deadlocks={d} livelocks={d}\n",
            .{ active_count, self.total_cycles_detected, self.total_deadlocks, self.total_livelocks },
        );
    }
};

/// Thread state information for diagnostics
pub const ThreadStateInfo = struct {
    state_str: []const u8 = "unknown",
    rip: u64 = 0,
    waiting_on: ?u64 = null,
};

/// Blocking classification result
pub const BlockingClassification = struct {
    type: BlockingType = .unknown,
    cycle: bool = false,
    description: []const u8 = "",
    condvar: ?u64 = null,
    mutex: ?u64 = null,
    address: ?u64 = null,
};

/// Blocking type
pub const BlockingType = enum {
    unknown,
    deadlock,
    livelock,
    waiting_condvar,
    waiting_mutex,
    spin_waiting,
    starvation,
    expected_idle,
    gpu_producer_starvation,
    ui_thread_starvation,
};

test "wait-for graph basic operations" {
    const allocator = std.testing.allocator;
    var graph = WaitForGraph.init(allocator);
    
    // Add nodes
    const thread1 = try graph.addNode(.thread, 0x1000, 0);
    const mutex1 = try graph.addNode(.mutex, 0x2000, 0x1000);
    const thread2 = try graph.addNode(.thread, 0x3000, 0);
    
    try std.testing.expect(thread1.active);
    try std.testing.expect(mutex1.active);
    try std.testing.expect(thread2.active);
    
    // Add edges
    try graph.addEdge(0x1000, 0x2000); // thread1 -> mutex1
    try graph.addEdge(0x3000, 0x2000); // thread2 -> mutex1
    
    try std.testing.expectEqual(@as(u8, 1), thread1.edge_count);
    try std.testing.expectEqual(@as(u8, 1), thread2.edge_count);
    
    // Remove node
    graph.removeNode(0x1000);
    try std.testing.expect(graph.findNode(0x1000) == null);
    try std.testing.expectEqual(@as(u8, 0), mutex1.edge_count); // Edge should be removed
}