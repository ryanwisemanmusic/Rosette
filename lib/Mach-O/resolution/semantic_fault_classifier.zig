const std = @import("std");

pub const FaultClass = enum {
    cxx_object_model_null_vtable,
    bad_this_pointer,
    bad_vtable_header,
    bad_streambuf_pointer,
    bad_typeinfo_pointer,
    bad_return_address,
    bad_import_thunk,
    bad_guest_stack,
    generic_memory,
};

pub const Context = struct {
    instruction: []const u8,
    symbol: []const u8,
    address: u64,
    rdi: u64,
    rsi: u64,
    rsp: u64,
    rbp: u64,
    rdi_mapped: bool,
    rsi_mapped: bool,
    stack_mapped: bool,
    vtable_header_mapped: bool = true,
    typeinfo_mapped: bool = true,
};

pub const Classification = struct {
    class: FaultClass,
    reason: []const u8,
    next_subsystem: []const u8,
};

pub fn classify(context: Context) Classification {
    const near_null = context.address < 0x1000 or context.address >= std.math.maxInt(u64) - 0x1000;
    const stream_symbol = std.mem.indexOf(u8, context.symbol, "basic_ostream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_istream") != null or
        std.mem.indexOf(u8, context.symbol, "basic_ios") != null;
    if (stream_symbol and near_null) {
        return .{
            .class = .cxx_object_model_null_vtable,
            .reason = "C++ stream code dereferenced a null/low vtable-derived address; the instruction is likely valid but object initialization is incomplete",
            .next_subsystem = "cxx_object_model / itanium_vtable_builder / libcpp_stream_bridge",
        };
    }
    if (stream_symbol and (!context.rsi_mapped or context.rsi < 0x1000)) {
        return .{ .class = .bad_streambuf_pointer, .reason = "stream constructor received an invalid streambuf pointer", .next_subsystem = "cxx_object_model / libcpp_stream_bridge" };
    }
    if (!context.vtable_header_mapped) {
        return .{ .class = .bad_vtable_header, .reason = "object vptr exists but its Itanium negative header is not readable", .next_subsystem = "itanium_vtable_builder" };
    }
    if (!context.typeinfo_mapped) {
        return .{ .class = .bad_typeinfo_pointer, .reason = "dynamic typeinfo pointer is not guest-backed", .next_subsystem = "itanium_dynamic_cast / itanium_vtable_builder" };
    }
    if (std.mem.eql(u8, context.instruction, "ret") and near_null) {
        return .{ .class = .bad_return_address, .reason = "RET selected an unmapped return address", .next_subsystem = "call stack / unwind runtime" };
    }
    if ((std.mem.indexOf(u8, context.instruction, "jmp") != null or std.mem.indexOf(u8, context.instruction, "call") != null) and near_null) {
        return .{ .class = .bad_import_thunk, .reason = "indirect import control transfer resolved to zero or a low address", .next_subsystem = "import resolver / dyld bindings" };
    }
    if (!context.stack_mapped) {
        return .{ .class = .bad_guest_stack, .reason = "RSP/RBP escaped the registered guest stack", .next_subsystem = "guest scheduler / stack allocator" };
    }
    if ((!context.rdi_mapped and context.rdi != 0) or (!context.rsi_mapped and context.rsi != 0)) {
        return .{ .class = .bad_this_pointer, .reason = "pointer-like argument is outside all guest mappings", .next_subsystem = "pointer_firewall / calling convention bridge" };
    }
    return .{ .class = .generic_memory, .reason = "memory access is outside the active guest mapping", .next_subsystem = "memory provenance / decoder" };
}

test "stream near-null faults identify object model rather than arithmetic" {
    const result = classify(.{
        .instruction = "add_reg64_mem64",
        .symbol = "__ZNSt3__113basic_ostreamIcEEC2EPNS_15basic_streambufIcEE",
        .address = std.math.maxInt(u64) - 23,
        .rdi = 0x1000,
        .rsi = 8,
        .rsp = 0x8000,
        .rbp = 0x8100,
        .rdi_mapped = true,
        .rsi_mapped = false,
        .stack_mapped = true,
    });
    try std.testing.expectEqual(FaultClass.cxx_object_model_null_vtable, result.class);
}
