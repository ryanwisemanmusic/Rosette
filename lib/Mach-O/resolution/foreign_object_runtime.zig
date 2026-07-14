const std = @import("std");

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
        if (std.mem.eql(u8, name, "g_signal_connect_data")) return .{ .handled = self.calls };
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
            std.debug.print(
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
        std.debug.print(
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

test "foreign UI constructors return dereferenceable typed guest objects" {
    const State = struct {
        memory: [1024]u8 = [_]u8{0} ** 1024,
        next: u64 = 64,
        regs: struct {
            rdi: u64 = 0,
            rsi: u64 = 0,
            rdx: u64 = 0,
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
