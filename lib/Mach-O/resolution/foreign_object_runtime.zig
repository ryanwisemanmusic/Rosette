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
        if (isConstructor(name)) {
            return .{ .handled = self.createObject(state, constructorTypeName(name)) orelse 0 };
        }
        if (isPointerGetter(name)) {
            return .{ .handled = self.createObject(state, name) orelse 0 };
        }
        if (std.mem.eql(u8, name, "gtk_init_check")) return .{ .handled = 1 };
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

    fn createObject(self: *Runtime, state: anytype, type_name: []const u8) ?u64 {
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
        };
        self.object_count += 1;
        self.allocations +|= 1;
        return address;
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
        regs: struct { rdi: u64 = 0 } = .{},

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

    try std.testing.expectEqual(@as(u64, 0), runtime.dispatch(&state, "_gtk_main_level").?.handled);
    try std.testing.expect(runtime.dispatch(&state, "_gtk_main").? == .handled_void);
    try std.testing.expectEqual(@as(u64, 1), runtime.main_loop_entries);
    try std.testing.expectEqual(@as(u64, 1), runtime.main_loop_bypasses);
    try std.testing.expectEqual(@as(u32, 0), runtime.main_loop_depth);
}
