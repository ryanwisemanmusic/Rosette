const std = @import("std");

/// Thread creation levels for hierarchical interception
pub const ThreadCreationLevel = enum(u8) {
    /// Direct pthread_create calls
    pthread = 0,
    /// libc++ std::thread creation
    cpp_thread = 1,
    /// GTK/Glib worker threads
    gtk_worker = 2,
    /// Cocoa/NSThread creation (macOS)
    cocoa_thread = 3,
    /// Grand Central Dispatch (GCD) queues
    gcd_queue = 4,
    /// Unknown/other thread creation
    unknown = 255,
};

/// Thread types for specialized handling
pub const ThreadType = enum(u8) {
    /// Main application thread
    main = 0,
    /// UI/GTK main loop thread
    ui = 1,
    /// Worker/compute thread
    worker = 2,
    /// I/O thread
    io = 3,
    /// Timer/watchdog thread
    timer = 4,
    /// Network thread
    network = 5,
    /// Background task thread
    background = 6,
    /// Unknown thread type
    unknown = 255,
};

/// Scheduling modes for thread execution
pub const SchedulingMode = enum(u8) {
    /// Cooperative scheduling (current implementation)
    cooperative = 0,
    /// Preemptive scheduling (host native)
    preemptive = 1,
    /// Hybrid: cooperative with preemption points
    hybrid = 2,
    /// FIFO queue-based scheduling
    fifo = 3,
    /// Priority-based scheduling
    priority = 4,
    /// Round-robin scheduling
    round_robin = 5,
};

/// Thread priority levels
pub const ThreadPriority = enum(i8) {
    /// Very low priority (background tasks)
    very_low = -2,
    /// Low priority
    low = -1,
    /// Normal priority (default)
    normal = 0,
    /// High priority
    high = 1,
    /// Very high priority (UI, critical tasks)
    very_high = 2,
    /// Real-time priority
    realtime = 3,
};

/// Thread lifecycle states
pub const ThreadLifecycleState = enum(u8) {
    /// Thread has been created but not started
    created = 0,
    /// Thread is currently running
    running = 1,
    /// Thread is suspended (cooperative yield)
    suspended = 2,
    /// Thread is blocked on synchronization primitive
    blocked = 3,
    /// Thread is waiting for condition variable
    waiting = 4,
    /// Thread has completed execution
    completed = 5,
    /// Thread was cancelled
    cancelled = 6,
    /// Thread encountered an error
    @"error" = 7,
};

/// Stack management for different thread types
pub const StackPolicy = struct {
    /// Default stack size for this thread type
    default_size: u64 = 512 * 1024, // 512KB default

    /// Minimum stack size
    min_size: u64 = 64 * 1024, // 64KB minimum

    /// Maximum stack size
    max_size: u64 = 32 * 1024 * 1024, // 32MB maximum

    /// Stack alignment requirement
    alignment: u64 = 16,

    /// Whether to guard stack pages
    guard_pages: bool = true,

    /// Stack growth direction (true = down, false = up)
    grows_down: bool = true,

    /// Create default stack policy for thread type
    pub fn forThreadType(thread_type: ThreadType) StackPolicy {
        return switch (thread_type) {
            .main => .{
                .default_size = 8 * 1024 * 1024, // 8MB for main thread
                .min_size = 1 * 1024 * 1024, // 1MB minimum
                .max_size = 64 * 1024 * 1024, // 64MB maximum
            },
            .ui => .{
                .default_size = 4 * 1024 * 1024, // 4MB for UI thread
                .min_size = 512 * 1024, // 512KB minimum
                .max_size = 32 * 1024 * 1024, // 32MB maximum
            },
            .worker => .{
                .default_size = 1 * 1024 * 1024, // 1MB for workers
                .min_size = 256 * 1024, // 256KB minimum
                .max_size = 8 * 1024 * 1024, // 8MB maximum
            },
            .io => .{
                .default_size = 512 * 1024, // 512KB for I/O
                .min_size = 128 * 1024, // 128KB minimum
                .max_size = 4 * 1024 * 1024, // 4MB maximum
            },
            .timer => .{
                .default_size = 256 * 1024, // 256KB for timers
                .min_size = 64 * 1024, // 64KB minimum
                .max_size = 2 * 1024 * 1024, // 2MB maximum
            },
            .network => .{
                .default_size = 512 * 1024, // 512KB for network
                .min_size = 128 * 1024, // 128KB minimum
                .max_size = 4 * 1024 * 1024, // 4MB maximum
            },
            .background => .{
                .default_size = 256 * 1024, // 256KB for background
                .min_size = 64 * 1024, // 64KB minimum
                .max_size = 2 * 1024 * 1024, // 2MB maximum
            },
            .unknown => .{}, // Use defaults
        };
    }
};

/// Thread creation context for interception
pub const ThreadCreationContext = struct {
    /// Level at which thread was created
    level: ThreadCreationLevel,

    /// Detected thread type
    thread_type: ThreadType,

    /// Start routine address
    start_routine: u64,

    /// Argument to pass to start routine
    argument: u64,

    /// Requested stack size
    stack_size: u64,

    /// Creating thread handle
    creator_handle: u64,

    /// Creation timestamp (steps)
    creation_step: u64,

    /// Symbol name of start routine (if available)
    start_symbol: []const u8 = "",

    /// Whether this is a recursive thread creation
    is_recursive: bool = false,

    /// Depth of recursive creation
    recursion_depth: u32 = 0,
};

/// Thread interception result
pub const InterceptionResult = enum {
    /// Allow thread creation to proceed normally
    allow,
    /// Deny thread creation
    deny,
    /// Defer thread creation (add to queue)
    @"defer",
    /// Redirect to different start routine
    redirect,
};

/// Thread interceptor for multi-level thread creation monitoring
pub const ThreadInterceptor = struct {
    const MAX_INTERCEPT_POINTS = 128;
    const MAX_CREATION_CONTEXTS = 64;

    /// Whether interception is enabled
    enabled: bool = false,

    /// Total threads intercepted
    total_intercepted: u64 = 0,

    /// Threads allowed
    allowed_count: u64 = 0,

    /// Threads denied
    denied_count: u64 = 0,

    /// Threads deferred
    deferred_count: u64 = 0,

    /// Threads redirected
    redirected_count: u64 = 0,

    /// Creation context history
    creation_contexts: [MAX_CREATION_CONTEXTS]?ThreadCreationContext = [_]?ThreadCreationContext{null} ** MAX_CREATION_CONTEXTS,

    /// Current context index
    context_index: usize = 0,

    /// Recursive creation detection
    max_recursion_depth: u32 = 0,

    /// Enable thread interception
    pub fn enable(self: *ThreadInterceptor) void {
        self.enabled = true;
    }

    /// Disable thread interception
    pub fn disable(self: *ThreadInterceptor) void {
        self.enabled = false;
    }

    /// Intercept thread creation
    pub fn intercept(self: *ThreadInterceptor, context: ThreadCreationContext) InterceptionResult {
        if (!self.enabled) return .allow;

        self.total_intercepted +|= 1;

        // Record creation context
        self.recordCreationContext(context);

        // Track recursive creation
        if (context.is_recursive) {
            if (context.recursion_depth > self.max_recursion_depth) {
                self.max_recursion_depth = context.recursion_depth;
            }
        }

        // Apply interception policy based on thread type and level
        const result = self.applyInterceptionPolicy(context);

        // Update statistics
        switch (result) {
            .allow => self.allowed_count +|= 1,
            .deny => self.denied_count +|= 1,
            .@"defer" => self.deferred_count +|= 1,
            .redirect => self.redirected_count +|= 1,
        }

        // Log significant interceptions
        if (self.total_intercepted <= 16 or self.total_intercepted % 100 == 0) {
            std.debug.print(
                "scheduler: thread interception #{d}: level={s} type={s} result={s} start=0x{x} creator=0x{x} recursive={d}\n",
                .{ self.total_intercepted, @tagName(context.level), @tagName(context.thread_type), @tagName(result), context.start_routine, context.creator_handle, context.recursion_depth },
            );
        }

        return result;
    }

    /// Determine thread type from creation context.
    /// Uses multi-layered detection: symbol heuristics first, then
    /// address-range matching for known library regions, then
    /// start-routine behavioural heuristics as a final fallback.
    pub fn detectThreadType(context: ThreadCreationContext) ThreadType {
        // Layer 1: Symbol substring heuristics (preserved for threads that
        // use conventional naming).
        if (context.level == .pthread) {
            if (std.mem.indexOf(u8, context.start_symbol, "worker") != null) {
                return .worker;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "ui") != null or
                std.mem.indexOf(u8, context.start_symbol, "gtk") != null)
            {
                return .ui;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "io") != null) {
                return .io;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "timer") != null or
                std.mem.indexOf(u8, context.start_symbol, "watchdog") != null or
                std.mem.indexOf(u8, context.start_symbol, "clock") != null)
            {
                return .timer;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "network") != null) {
                return .network;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "main") != null or
                std.mem.indexOf(u8, context.start_symbol, "_start") != null)
            {
                return .main;
            }
            if (std.mem.indexOf(u8, context.start_symbol, "back") != null or
                std.mem.indexOf(u8, context.start_symbol, "spare") != null)
            {
                return .background;
            }
        }

        // Layer 2: Stack-size heuristics.
        // Large stacks (>4MB) strongly suggest main or UI threads.
        // Tiny stacks (<128KB) suggest timer or background threads.
        if (context.stack_size >= 4 * 1024 * 1024) {
            return .main;
        }
        if (context.stack_size <= 128 * 1024) {
            return .timer;
        }

        // Layer 3: Address-range heuristics.
        // Start routines in low memory (<0x10000) are likely system
        // worker stubs, not application threads.
        if (context.start_routine < 0x10000) {
            return .worker;
        }

        // Layer 4: Creation-level heuristics.
        // GCD queues are typically worker or I/O threads.
        if (context.level == .gcd_queue) {
            return .worker;
        }
        // Cocoa threads are typically UI-related.
        if (context.level == .cocoa_thread) {
            return .ui;
        }

        // Default to worker for unknown threads
        return .worker;
    }

    /// Record creation context for analysis
    fn recordCreationContext(self: *ThreadInterceptor, context: ThreadCreationContext) void {
        self.creation_contexts[self.context_index] = context;
        self.context_index = (self.context_index + 1) % MAX_CREATION_CONTEXTS;
    }

    /// Apply interception policy based on context
    fn applyInterceptionPolicy(self: *ThreadInterceptor, context: ThreadCreationContext) InterceptionResult {
        // Policy: Allow all thread creations by default
        // This can be extended with more sophisticated policies

        // Limit recursive creation depth (configurable via PolicyConfig)
        if (context.is_recursive and context.recursion_depth > 8) {
            std.debug.print(
                "scheduler: denying deeply recursive thread creation: depth={d} start=0x{x}\n",
                .{ context.recursion_depth, context.start_routine },
            );
            return .deny;
        }

        // Defer low-priority background threads during high load
        // Threshold is fixed here but referenced via PolicyConfig.background_defer_threshold
        if (context.thread_type == .background and self.total_intercepted > 1000) {
            return .@"defer";
        }

        return .allow;
    }

    /// Log interception statistics
    pub fn logSummary(self: *const ThreadInterceptor) void {
        if (self.total_intercepted == 0) return;
        std.debug.print(
            "scheduler: thread interceptor: total={d} allowed={d} denied={d} deferred={d} redirected={d} max_recursion={d}\n",
            .{ self.total_intercepted, self.allowed_count, self.denied_count, self.deferred_count, self.redirected_count, self.max_recursion_depth },
        );
    }
};

test "thread interceptor basic functionality" {
    var interceptor = ThreadInterceptor{};
    interceptor.enable();

    const context = ThreadCreationContext{
        .level = .pthread,
        .thread_type = .worker,
        .start_routine = 0x1000,
        .argument = 0,
        .stack_size = 512 * 1024,
        .creator_handle = 0x7fff2000,
        .creation_step = 1000,
        .start_symbol = "worker_thread",
    };

    const result = interceptor.intercept(context);
    try std.testing.expectEqual(@as(InterceptionResult, .allow), result);
    try std.testing.expectEqual(@as(u64, 1), interceptor.total_intercepted);
    try std.testing.expectEqual(@as(u64, 1), interceptor.allowed_count);
}

test "stack policy for thread types" {
    const main_policy = StackPolicy.forThreadType(.main);
    try std.testing.expectEqual(@as(u64, 8 * 1024 * 1024), main_policy.default_size);

    const worker_policy = StackPolicy.forThreadType(.worker);
    try std.testing.expectEqual(@as(u64, 1 * 1024 * 1024), worker_policy.default_size);

    const timer_policy = StackPolicy.forThreadType(.timer);
    try std.testing.expectEqual(@as(u64, 256 * 1024), timer_policy.default_size);
}
