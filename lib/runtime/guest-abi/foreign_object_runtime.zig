const std = @import("std");
const machoCapturePrint = @import("event_log").machoCapturePrint;

const MAX_TYPES = 128;
const MAX_OBJECTS = 512;
const OBJECT_SIZE: u64 = 64;
const CLASS_SIZE: u64 = 64;

pub const Outcome = union(enum) {
    handled: u64,
    handled_void,
};

const TypeEntry = struct {
    active: bool = false,
    name: []const u8 = "",
    id: u64 = 0,
    class: u64 = 0,
};

const ObjectEntry = struct {
    active: bool = false,
    address: u64 = 0,
    type_id: u64 = 0,
    references: u64 = 0,
    parent: u64 = 0,
    getter_name: []const u8 = "",
};

/// A `g_signal_connect_data` registration Rosette can actually deliver.
///
/// The previous model answered the call with a handler id and dropped the
/// callback. That is invisible until something *emits* the signal — and GTK's
/// paint path is exactly that: `gtk_widget_queue_draw` schedules the widget's
/// `draw` handler, and a presenter that never sees its handler run never
/// paints. Recording the registration is what makes the emission possible.
pub const SignalHandler = struct {
    active: bool = false,
    instance: u64 = 0,
    callback: u64 = 0,
    data: u64 = 0,
    /// Interned signal name. Only the signals Rosette can emit are retained;
    /// everything else is counted as dropped rather than silently accepted, so
    /// a missing emission is visible as a number instead of as silence.
    signal: Signal = .other,
    /// The queued dispatch for this handler, while one is outstanding. GTK
    /// coalesces: a widget is marked dirty and painted once, however many
    /// times `queue_draw` is called before the paint happens.
    pending_source: u64 = 0,
};

pub const Signal = enum { draw, other };

const MAX_SIGNAL_HANDLERS = 32;

pub const Runtime = struct {
    types: [MAX_TYPES]TypeEntry = [_]TypeEntry{.{}} ** MAX_TYPES,
    objects: [MAX_OBJECTS]ObjectEntry = [_]ObjectEntry{.{}} ** MAX_OBJECTS,
    type_count: usize = 0,
    object_count: usize = 0,
    calls: u64 = 0,
    allocations: u64 = 0,
    references: u64 = 0,
    mutations: u64 = 0,
    rejected: u64 = 0,
    main_loop_entries: u64 = 0,
    main_loop_bypasses: u64 = 0,
    main_loop_quits: u64 = 0,
    main_loop_depth: u32 = 0,
    signal_handlers: [MAX_SIGNAL_HANDLERS]SignalHandler = [_]SignalHandler{.{}} ** MAX_SIGNAL_HANDLERS,
    signal_connects: u64 = 0,
    signal_connects_dropped: u64 = 0,
    draw_requests: u64 = 0,
    draw_dispatches: u64 = 0,
    draw_coalesced: u64 = 0,

    /// `gulong g_signal_connect_data(instance, detailed_signal, handler, data,
    /// destroy_notify, flags)` — System V: rdi, rsi, rdx, rcx, r8, r9.
    ///
    /// Only signals Rosette can emit are retained. A returned id is a real
    /// index+1 so `g_signal_handler_disconnect` could find it later; ids for
    /// dropped signals stay distinct so the guest never sees two registrations
    /// share one id.
    fn connectSignal(self: *Runtime, state: anytype) u64 {
        self.signal_connects +|= 1;
        const instance = state.regs.rdi;
        const callback = state.regs.rdx;
        const data = state.regs.rcx;
        const name = state.guestCString(state.regs.rsi, 64) orelse "";
        // GTK detailed signal names may carry a "::detail" suffix.
        const base = name[0 .. std.mem.indexOfScalar(u8, name, ':') orelse name.len];
        const signal: Signal = if (std.mem.eql(u8, base, "draw")) .draw else .other;
        if (signal == .other or instance == 0 or callback == 0) {
            self.signal_connects_dropped +|= 1;
            return self.calls;
        }
        for (&self.signal_handlers, 0..) |*entry, index| {
            if (entry.active and !(entry.instance == instance and entry.signal == signal)) continue;
            const first = !entry.active;
            entry.* = .{
                .active = true,
                .instance = instance,
                .callback = callback,
                .data = data,
                .signal = signal,
            };
            if (first) {
                machoCapturePrint(
                    "macho-processor: GTK signal handler retained: signal={s} instance=0x{x} callback=0x{x} data=0x{x}; queue_draw on this widget can now reach its handler, which is what lets a presenter paint\n",
                    .{ base, instance, callback, data },
                );
            }
            return index + 1;
        }
        self.signal_connects_dropped +|= 1;
        return self.calls;
    }

    /// `gtk_widget_queue_draw(widget)` — GTK schedules the widget's `draw`
    /// handler on the UI thread. Modelled by queueing that handler on the same
    /// cooperative dispatch the idle sources already use.
    ///
    /// Without this the guest's paint request went nowhere: a presenter that
    /// latches "paint already requested" until its handler runs stops asking
    /// after the first request, so one dropped emission silences every
    /// subsequent frame rather than one.
    fn requestDraw(self: *Runtime, state: anytype, widget: u64) void {
        self.draw_requests +|= 1;
        if (widget == 0) return;
        for (&self.signal_handlers) |*entry| {
            if (!entry.active or entry.signal != .draw or entry.instance != widget) continue;
            // Coalesce, because that is what GTK does: the widget is marked
            // dirty and painted once, however many times `queue_draw` is called
            // before the paint runs. Queueing one callback per call instead
            // fills a bounded queue with duplicate paints and starves the
            // sources that pump the guest's main loop — the paint would arrive
            // by crowding out the thing that makes progress.
            if (state.isIdleCallbackPending(entry.pending_source)) {
                self.draw_coalesced +|= 1;
                return;
            }
            // GTK3: gboolean draw(GtkWidget *widget, cairo_t *cr, gpointer data).
            // The cairo context is null: Rosette has no cairo surface, and a
            // handler that dereferences it would fault here rather than
            // silently draw nothing. Xenia's handler compares the widget and
            // calls its own painter, which is the shape this models.
            const source = state.scheduleSignalCallback(entry.callback, widget, 0, entry.data, "gtk_draw");
            if (source == 0) return;
            entry.pending_source = source;
            self.draw_dispatches +|= 1;
            if (self.draw_dispatches <= 4) {
                machoCapturePrint(
                    "macho-processor: GTK draw dispatch #{d}: widget=0x{x} handler=0x{x} data=0x{x} source={d} requests={d}\n",
                    .{ self.draw_dispatches, widget, entry.callback, entry.data, source, self.draw_requests },
                );
            }
            return;
        }
    }

    pub fn dispatch(self: *Runtime, state: anytype, symbol: []const u8) ?Outcome {
        const name = normalize(symbol);
        if (!isForeignUiSymbol(name)) return null;
        self.calls +|= 1;

        if (std.mem.endsWith(u8, name, "_get_type")) {
            return .{ .handled = self.typeFor(state, name) orelse 0 };
        }
        if (std.mem.eql(u8, name, "g_type_check_instance_cast")) {
            return .{ .handled = if (self.isObject(state.regs.rdi)) state.regs.rdi else 0 };
        }
        if (std.mem.eql(u8, name, "g_type_check_instance_is_a")) {
            return .{ .handled = @intFromBool(self.isObject(state.regs.rdi)) };
        }
        if (std.mem.eql(u8, name, "g_object_ref_sink") or std.mem.eql(u8, name, "g_object_ref")) {
            if (self.findObject(state.regs.rdi)) |object| object.references +|= 1;
            self.references +|= 1;
            return .{ .handled = state.regs.rdi };
        }
        if (std.mem.eql(u8, name, "g_object_unref")) {
            if (self.findObject(state.regs.rdi)) |object| object.references -|= 1;
            self.references +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_init_check")) {
            return .{ .handled = @intFromBool(ensureNativeApplication(state)) };
        }
        if (isConstructor(name)) {
            const object = self.createObject(state, constructorTypeName(name), 0, "") orelse 0;
            if (std.mem.eql(u8, name, "gtk_window_new") and object != 0 and !ensureNativeWindow(state)) {
                self.rejected +|= 1;
                return .{ .handled = 0 };
            }
            return .{ .handled = object };
        }
        if (std.mem.eql(u8, name, "gtk_window_set_title")) {
            const title = state.guestCString(state.regs.rsi, 4096) orelse "Xenia Canary (Rosette)";
            _ = setNativeWindowTitle(state, title);
            self.mutations +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_widget_set_size_request")) {
            const width: i32 = @bitCast(@as(u32, @truncate(state.regs.rsi)));
            const height: i32 = @bitCast(@as(u32, @truncate(state.regs.rdx)));
            if (width > 0 and height > 0) _ = setNativeWindowSize(state, width, height);
            self.mutations +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_widget_show_all") or
            std.mem.eql(u8, name, "gtk_window_activate_focus"))
        {
            _ = showNativeWindow(state);
            self.mutations +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_window_fullscreen") or
            std.mem.eql(u8, name, "gtk_window_unfullscreen"))
        {
            _ = setNativeWindowFullscreen(state, std.mem.eql(u8, name, "gtk_window_fullscreen"));
            self.mutations +|= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_widget_get_allocation")) {
            writeNativeAllocation(state, state.regs.rsi);
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gdk_window_get_width")) {
            return .{ .handled = nativeWindowWidth(state) };
        }
        if (std.mem.eql(u8, name, "gdk_window_get_height")) {
            return .{ .handled = nativeWindowHeight(state) };
        }
        if (std.mem.eql(u8, name, "gdk_quartz_window_get_nsview")) {
            return .{ .handled = nativeViewToken(state) };
        }
        if (isPointerGetter(name)) {
            return .{ .handled = self.associatedObject(state, name, state.regs.rdi) orelse 0 };
        }
        if (std.mem.eql(u8, name, "g_signal_connect_data")) {
            return .{ .handled = self.connectSignal(state) };
        }
        if (std.mem.eql(u8, name, "gtk_widget_queue_draw") or
            std.mem.eql(u8, name, "gtk_widget_queue_draw_area") or
            std.mem.eql(u8, name, "gtk_widget_queue_draw_region"))
        {
            self.requestDraw(state, state.regs.rdi);
            return .handled_void;
        }
        if (isBooleanQuery(name)) return .{ .handled = @intFromBool(self.isObject(state.regs.rdi)) };
        if (std.mem.eql(u8, name, "gtk_main_level")) {
            return .{ .handled = self.main_loop_depth };
        }
        if (std.mem.eql(u8, name, "gtk_main_quit")) {
            self.main_loop_quits +|= 1;
            if (self.main_loop_depth != 0) self.main_loop_depth -= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_main")) {
            self.main_loop_entries +|= 1;
            self.main_loop_depth +|= 1;
            self.main_loop_bypasses +|= 1;
            machoCapturePrint(
                "macho-processor: GTK main loop bypass #{d}: no cooperative guest-thread/event dispatcher is active; returning from gtk_main will initiate guest shutdown\n",
                .{self.main_loop_bypasses},
            );
            self.main_loop_depth -= 1;
            return .handled_void;
        }
        if (std.mem.eql(u8, name, "gtk_dialog_run")) {
            return .{ .handled = 0 };
        }

        self.mutations +|= 1;
        return .handled_void;
    }

    pub fn logSummary(self: *const Runtime) void {
        machoCapturePrint(
            "macho-processor: foreign object runtime: calls={d} types={d} objects={d} allocations={d} refs={d} mutations={d} rejected={d} main_loop(entries/bypasses/quits/depth)={d}/{d}/{d}/{d}\n",
            .{ self.calls, self.type_count, self.object_count, self.allocations, self.references, self.mutations, self.rejected, self.main_loop_entries, self.main_loop_bypasses, self.main_loop_quits, self.main_loop_depth },
        );
    }

    fn createObject(self: *Runtime, state: anytype, type_name: []const u8, parent: u64, getter_name: []const u8) ?u64 {
        if (self.object_count >= self.objects.len) {
            self.rejected +|= 1;
            return null;
        }
        const type_id = self.typeFor(state, type_name) orelse return null;
        const class = self.classFor(type_id) orelse return null;
        const address = state.guestAlloc(OBJECT_SIZE, 16) orelse {
            self.rejected +|= 1;
            return null;
        };
        const bytes = state.guestMemory(address, OBJECT_SIZE) orelse return null;
        @memset(bytes, 0);
        state.write64(address, class);
        self.objects[self.object_count] = .{
            .active = true,
            .address = address,
            .type_id = type_id,
            .references = 1,
            .parent = parent,
            .getter_name = getter_name,
        };
        self.object_count += 1;
        self.allocations +|= 1;
        return address;
    }

    fn associatedObject(self: *Runtime, state: anytype, getter_name: []const u8, parent: u64) ?u64 {
        for (self.objects[0..self.object_count]) |object| {
            if (object.parent == parent and std.mem.eql(u8, object.getter_name, getter_name)) return object.address;
        }
        return self.createObject(state, getter_name, parent, getter_name);
    }

    fn typeFor(self: *Runtime, state: anytype, name: []const u8) ?u64 {
        for (self.types[0..self.type_count]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.id;
        }
        if (self.type_count >= self.types.len) {
            self.rejected +|= 1;
            return null;
        }
        const class = state.guestAlloc(CLASS_SIZE, 16) orelse return null;
        const bytes = state.guestMemory(class, CLASS_SIZE) orelse return null;
        @memset(bytes, 0);
        const id = 0x1000 + @as(u64, @intCast(self.type_count + 1)) * 16;
        state.write64(class, id);
        self.types[self.type_count] = .{ .active = true, .name = name, .id = id, .class = class };
        self.type_count += 1;
        return id;
    }

    fn classFor(self: *Runtime, type_id: u64) ?u64 {
        for (self.types[0..self.type_count]) |entry| {
            if (entry.id == type_id) return entry.class;
        }
        return null;
    }

    fn findObject(self: *Runtime, address: u64) ?*ObjectEntry {
        for (&self.objects) |*object| {
            if (object.active and object.address == address) return object;
        }
        return null;
    }

    fn isObject(self: *Runtime, address: u64) bool {
        return self.findObject(address) != null;
    }
};

fn StateType(comptime StatePointer: type) type {
    return @typeInfo(StatePointer).pointer.child;
}

fn ensureNativeApplication(state: anytype) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "ensureNativeApplication")) return state.ensureNativeApplication();
    return true;
}

fn ensureNativeWindow(state: anytype) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "ensureNativeWindow")) return state.ensureNativeWindow();
    return true;
}

fn setNativeWindowTitle(state: anytype, title: []const u8) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "setNativeWindowTitle")) return state.setNativeWindowTitle(title);
    return true;
}

fn setNativeWindowSize(state: anytype, width: i32, height: i32) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "setNativeWindowSize")) return state.setNativeWindowSize(width, height);
    return true;
}

fn showNativeWindow(state: anytype) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "showNativeWindow")) return state.showNativeWindow();
    return true;
}

fn setNativeWindowFullscreen(state: anytype, fullscreen: bool) bool {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "setNativeWindowFullscreen")) return state.setNativeWindowFullscreen(fullscreen);
    return true;
}

fn nativeViewToken(state: anytype) u64 {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "nativeViewToken")) return state.nativeViewToken();
    return 0;
}

fn nativeWindowWidth(state: anytype) u32 {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "nativeWindowWidth")) return state.nativeWindowWidth();
    return 1280;
}

fn nativeWindowHeight(state: anytype) u32 {
    const State = StateType(@TypeOf(state));
    if (@hasDecl(State, "nativeWindowHeight")) return state.nativeWindowHeight();
    return 720;
}

fn writeNativeAllocation(state: anytype, output: u64) void {
    if (output == 0 or state.guestMemory(output, 16) == null) return;
    state.write32(output, 0);
    state.write32(output + 4, 0);
    state.write32(output + 8, nativeWindowWidth(state));
    state.write32(output + 12, nativeWindowHeight(state));
}

fn normalize(symbol: []const u8) []const u8 {
    return if (symbol.len != 0 and symbol[0] == '_') symbol[1..] else symbol;
}

fn isForeignUiSymbol(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "gtk_") or
        std.mem.startsWith(u8, name, "gdk_") or
        std.mem.startsWith(u8, name, "g_object_") or
        std.mem.startsWith(u8, name, "g_type_") or
        std.mem.startsWith(u8, name, "g_signal_");
}

fn isConstructor(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "_new") != null or std.mem.endsWith(u8, name, "_create");
}

fn constructorTypeName(name: []const u8) []const u8 {
    const marker = std.mem.indexOf(u8, name, "_new") orelse return name;
    return name[0..marker];
}

fn isPointerGetter(name: []const u8) bool {
    const suffixes = [_][]const u8{ "_get_submenu", "_get_window", "_get_child", "_get_content_area", "_get_widget" };
    for (suffixes) |suffix| if (std.mem.endsWith(u8, name, suffix)) return true;
    return false;
}

fn isBooleanQuery(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "_has_") != null or
        std.mem.indexOf(u8, name, "_is_") != null or
        std.mem.endsWith(u8, name, "_get_visible");
}

test "queue_draw reaches the connected draw handler" {
    // The paint path this models: GTK schedules a widget's `draw` handler when
    // `gtk_widget_queue_draw` is called. A presenter that latches "paint
    // already requested" until its handler runs stops asking after the first
    // request, so dropping the registration silences every later frame — which
    // is why the connection has to be retained and the emission delivered.
    const State = struct {
        memory: [1024]u8 = [_]u8{0} ** 1024,
        next: u64 = 64,
        regs: struct {
            rdi: u64 = 0,
            rsi: u64 = 0,
            rdx: u64 = 0,
            rcx: u64 = 0,
        } = .{},
        scheduled_function: u64 = 0,
        scheduled_args: [3]u64 = .{ 0, 0, 0 },
        schedule_calls: u64 = 0,
        pending_source: u64 = 0,

        fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
            const address = std.mem.alignForward(u64, self.next, alignment);
            if (address + size > self.memory.len) return null;
            self.next = address + size;
            return address;
        }
        fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
            if (address + size > self.memory.len) return null;
            return self.memory[@intCast(address)..@intCast(address + size)];
        }
        fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.memory[@intCast(address)..][0..4], value, .little);
        }
        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.memory[@intCast(address)..][0..8], value, .little);
        }

        fn guestCString(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
            if (address >= self.memory.len) return null;
            const bytes = self.memory[@intCast(address)..@min(self.memory.len, @as(usize, @intCast(address)) + maximum)];
            const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
            return bytes[0..end];
        }
        fn scheduleSignalCallback(self: *@This(), function: u64, a0: u64, a1: u64, a2: u64, tag: []const u8) u64 {
            _ = tag;
            self.schedule_calls += 1;
            self.scheduled_function = function;
            self.scheduled_args = .{ a0, a1, a2 };
            self.pending_source = self.schedule_calls;
            return self.schedule_calls;
        }
        fn isIdleCallbackPending(self: *@This(), source: u64) bool {
            return source != 0 and source == self.pending_source;
        }
    };

    var runtime = Runtime{};
    var state = State{};
    @memcpy(state.memory[0..5], "draw\x00");

    const widget: u64 = 0xAAAA;
    const handler: u64 = 0xBBBB;
    const user_data: u64 = 0xCCCC;
    state.regs = .{ .rdi = widget, .rsi = 0, .rdx = handler, .rcx = user_data };
    const id = runtime.dispatch(&state, "_g_signal_connect_data").?.handled;
    try std.testing.expect(id != 0);

    // Emitting on that widget delivers (widget, cr=null, user_data).
    state.regs = .{ .rdi = widget };
    _ = runtime.dispatch(&state, "_gtk_widget_queue_draw").?;
    try std.testing.expectEqual(@as(u64, 1), state.schedule_calls);
    try std.testing.expectEqual(handler, state.scheduled_function);
    try std.testing.expectEqual([3]u64{ widget, 0, user_data }, state.scheduled_args);
    try std.testing.expectEqual(@as(u64, 1), runtime.draw_dispatches);

    // A different widget has no handler, so nothing is scheduled — the model
    // must not invent an emission for a widget the guest never connected.
    state.regs = .{ .rdi = 0xDEAD };
    _ = runtime.dispatch(&state, "_gtk_widget_queue_draw").?;
    try std.testing.expectEqual(@as(u64, 1), state.schedule_calls);
    try std.testing.expectEqual(@as(u64, 2), runtime.draw_requests);

    // A second request before the first is serviced must coalesce, exactly as
    // GTK does. Queueing a callback per call would fill a bounded queue with
    // duplicate paints and starve the guest's main-loop pump.
    state.regs = .{ .rdi = widget };
    _ = runtime.dispatch(&state, "_gtk_widget_queue_draw").?;
    try std.testing.expectEqual(@as(u64, 1), state.schedule_calls);
    try std.testing.expectEqual(@as(u64, 1), runtime.draw_coalesced);
    try std.testing.expectEqual(@as(u64, 1), runtime.draw_dispatches);

    // Once the queued paint has been serviced, the next request schedules again.
    state.pending_source = 0;
    state.regs = .{ .rdi = widget };
    _ = runtime.dispatch(&state, "_gtk_widget_queue_draw").?;
    try std.testing.expectEqual(@as(u64, 2), state.schedule_calls);
    try std.testing.expectEqual(@as(u64, 2), runtime.draw_dispatches);

    // A signal Rosette cannot emit is counted as dropped rather than retained.
    @memcpy(state.memory[16..23], "clicked");
    state.memory[23] = 0;
    state.regs = .{ .rdi = widget, .rsi = 16, .rdx = handler, .rcx = user_data };
    _ = runtime.dispatch(&state, "_g_signal_connect_data").?;
    try std.testing.expectEqual(@as(u64, 1), runtime.signal_connects_dropped);
}

test "foreign UI constructors return dereferenceable typed guest objects" {
    const State = struct {
        memory: [1024]u8 = [_]u8{0} ** 1024,
        next: u64 = 64,
        regs: struct {
            rdi: u64 = 0,
            rsi: u64 = 0,
            rdx: u64 = 0,
            rcx: u64 = 0,
        } = .{},

        fn guestAlloc(self: *@This(), size: u64, alignment: u64) ?u64 {
            const address = std.mem.alignForward(u64, self.next, alignment);
            if (address + size > self.memory.len) return null;
            self.next = address + size;
            return address;
        }
        fn guestMemory(self: *@This(), address: u64, size: u64) ?[]u8 {
            if (address + size > self.memory.len) return null;
            return self.memory[@intCast(address)..@intCast(address + size)];
        }
        fn guestCString(self: *@This(), address: u64, maximum: usize) ?[]const u8 {
            if (address >= self.memory.len) return null;
            const bytes = self.memory[@intCast(address)..@min(self.memory.len, @as(usize, @intCast(address)) + maximum)];
            const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
            return bytes[0..end];
        }
        fn scheduleSignalCallback(self: *@This(), function: u64, a0: u64, a1: u64, a2: u64, tag: []const u8) u64 {
            _ = self;
            _ = function;
            _ = a0;
            _ = a1;
            _ = a2;
            _ = tag;
            return 0;
        }
        fn isIdleCallbackPending(self: *@This(), source: u64) bool {
            _ = self;
            _ = source;
            return false;
        }
        fn write32(self: *@This(), address: u64, value: u32) void {
            std.mem.writeInt(u32, self.memory[@intCast(address)..][0..4], value, .little);
        }
        fn write64(self: *@This(), address: u64, value: u64) void {
            std.mem.writeInt(u64, self.memory[@intCast(address)..][0..8], value, .little);
        }
        fn read64(self: *@This(), address: u64) u64 {
            return std.mem.readInt(u64, self.memory[@intCast(address)..][0..8], .little);
        }
    };

    var runtime = Runtime{};
    var state = State{};
    const object = runtime.dispatch(&state, "_gtk_menu_bar_new").?.handled;
    try std.testing.expect(object > 1);
    const class = state.read64(object);
    try std.testing.expect(class > 1);
    try std.testing.expect(state.read64(class) > 1);

    state.regs.rdi = object;
    try std.testing.expectEqual(object, runtime.dispatch(&state, "_g_object_ref_sink").?.handled);
    try std.testing.expectEqual(object, runtime.dispatch(&state, "_g_type_check_instance_cast").?.handled);

    const first_window = runtime.dispatch(&state, "_gtk_widget_get_window").?.handled;
    const second_window = runtime.dispatch(&state, "_gtk_widget_get_window").?.handled;
    try std.testing.expect(first_window != 0);
    try std.testing.expectEqual(first_window, second_window);

    state.regs.rsi = 800;
    try std.testing.expect(runtime.dispatch(&state, "_gtk_widget_get_allocation").? == .handled_void);
    try std.testing.expectEqual(@as(u32, 1280), std.mem.readInt(u32, state.memory[808..812], .little));
    try std.testing.expectEqual(@as(u32, 720), std.mem.readInt(u32, state.memory[812..816], .little));

    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_gtk_main_level").?.handled);
    try std.testing.expect(runtime.dispatch(&state, "_gtk_main").? == .handled_void);
    try std.testing.expectEqual(@as(u64, 1), runtime.main_loop_entries);
    try std.testing.expectEqual(@as(u64, 1), runtime.main_loop_bypasses);
    try std.testing.expectEqual(@as(u32, 0), runtime.main_loop_depth);
}
