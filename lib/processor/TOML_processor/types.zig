const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    array: std.ArrayListUnmanaged(Value), // inline arrays only, NOT array-of-tables
    table: Table,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |*arr| {
                for (arr.items) |*item| item.deinit(allocator);
                arr.deinit(allocator);
            },
            .table => |*t| t.deinit(allocator),
            else => {},
        }
    }
};

pub const Table = struct {
    entries: std.StringArrayHashMapUnmanaged(Value),
    table_arrays: std.StringArrayHashMapUnmanaged(std.ArrayListUnmanaged(Table)),

    pub fn init() Table {
        return .{ .entries = .{}, .table_arrays = .{} };
    }

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        {
            var it = self.entries.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.*.deinit(allocator);
            }
            self.entries.deinit(allocator);
        }
        {
            var it = self.table_arrays.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                for (entry.value_ptr.*.items) |*t| t.deinit(allocator);
                entry.value_ptr.*.deinit(allocator);
            }
            self.table_arrays.deinit(allocator);
        }
    }

    pub fn get(self: *const Table, key: []const u8) ?*const Value {
        return self.entries.getPtr(key);
    }

    pub fn getPtr(self: *Table, key: []const u8) ?*Value {
        return self.entries.getPtr(key);
    }

    pub fn put(self: *Table, allocator: std.mem.Allocator, key: []const u8, value: Value) !void {
        const gop = try self.entries.getOrPut(allocator, key);
        if (gop.found_existing) {
            gop.value_ptr.*.deinit(allocator);
        } else {
            gop.key_ptr.* = try allocator.dupe(u8, key);
        }
        gop.value_ptr.* = value;
    }

    pub fn getTableArray(self: *const Table, key: []const u8) ?*const std.ArrayListUnmanaged(Table) {
        return self.table_arrays.getPtr(key);
    }

    pub fn getTableArrayMut(self: *Table, key: []const u8) ?*std.ArrayListUnmanaged(Table) {
        return self.table_arrays.getPtr(key);
    }

    pub fn getTableArrayKeys(self: *const Table) []const []const u8 {
        return self.table_arrays.keys();
    }

    pub fn getOrCreateTableArray(self: *Table, allocator: std.mem.Allocator, key: []const u8) !*std.ArrayListUnmanaged(Table) {
        const gop = try self.table_arrays.getOrPut(allocator, key);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, key);
            gop.value_ptr.* = .empty;
        }
        return gop.value_ptr;
    }

    pub fn keys(self: *const Table) []const []const u8 {
        return self.entries.keys();
    }

    pub fn count(self: *const Table) usize {
        return self.entries.count();
    }
};

pub const ParseError = error{
    FileTooLarge,
    InvalidUtf8,
    EmbeddedNul,
    InvalidCharacter,
    UnterminatedString,
    InvalidEscape,
    InvalidValue,
    UnexpectedToken,
    DuplicateKey,
    InvalidTableHeader,
    UnterminatedTableHeader,
    InvalidArrayOfTables,
    OutOfMemory,
    UnterminatedArray,
    IntegerOverflow,
};
