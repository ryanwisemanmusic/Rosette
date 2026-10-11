//! Vulkan's `robustBufferAccess` for a Metal device: every dynamically
//! indexed array access in a shader is clamped into its array before MoltenVK
//! sees the module.
//!
//! ## Why Rosette has to supply it
//!
//! Xenia creates its device with `robustBufferAccess` enabled
//! (`ui/vulkan/vulkan_device.cc`: `XE_UI_VULKAN_FEATURE(robustBufferAccess)`),
//! and its relative constant addressing indexes a 256-entry uniform array
//! without clamping the computed index. Loop-relative indices can escape it
//! by thousands of entries. FSI EDRAM addresses stay within complete tiles;
//! vertex fetch and memexport are mostly guarded by Xenia already. Those are
//! not established causes of the observed GPU faults.
//!
//! On a Windows or Linux driver those accesses are harmless, because
//! robustBufferAccess keeps them inside the bound range. MoltenVK reports the
//! feature, but Metal has no bounds checking: an index outside a buffer reads
//! or writes whatever that address names, and outside the allocation's pages
//! the GPU takes an address fault (`kIOGPUCommandBufferCallbackErrorPageFault`).
//! A second fault puts the process in macOS's GPU penalty box: every later
//! command buffer is ignored (`SubmissionsIgnored`), MoltenVK reports the
//! device lost, and Xenia exits. Three Halo 3 FSI campaign runs ended exactly
//! that way, with the longest FSI command buffer at 95 ms - not a timeout.
//!
//! ## What this does
//!
//! For every `OpAccessChain` / `OpInBoundsAccessChain` in a function, each
//! index that walks into an array, vector or matrix and is not a constant
//! already in bounds is replaced by an unsigned clamp:
//!
//!   - a run-time array (a storage buffer's `[]`): `min(index, max(len, 1) - 1)`
//!     where `len` is `OpArrayLength`, i.e. the bound descriptor range. For a
//!     buffer variable it is computed once at the top of each function;
//!   - a fixed array of `N` elements (uniform, push-constant, private,
//!     function, workgroup, or an array of descriptors): `min(index, N - 1)`;
//!   - a vector or matrix: `min(index, components - 1)`.
//!
//! The index is reinterpreted as unsigned first, so a negative index is a huge
//! one and lands on the last element. That is an outcome core
//! robustBufferAccess permits - out-of-bounds loads may return "values from
//! anywhere within the memory range(s) bound to the buffer", and stores "may
//! modify values within the memory range(s) bound to the buffer" - so a shader
//! that was correct under the core Vulkan robustness contract stays bounded.
//! Uniform-block loads additionally return zero when the original index is
//! outside the array, instead of substituting an unrelated edge constant.
//! This matches Direct3D constant-buffer behavior and avoids manufacturing
//! lighting/transform values from c[255]. The actual load remains clamped:
//! selecting zero after an unsafe load would not protect the GPU.
//! Xenia's own vertex fetch still returns
//! zero past `fetch_end`; only the load it discards is moved in bounds.
//!
//! Shader inputs and outputs are left alone: their dynamic indices are
//! tessellation invocation ids, which are in range by construction, and
//! MoltenVK's tessellation emulation pattern-matches exactly those accesses.
//!
//! Nothing else in the module changes. A module the walker cannot read is
//! returned untouched and the reason is reported; a dynamic index whose shape
//! the walker does not cover is left as it was and counted, so it is visible
//! in the run log rather than silently assumed safe.

const std = @import("std");

pub const magic: u32 = 0x0723_0203;

/// Ids are allocated after the module's own bound. MoltenVK and SPIRV-Cross
/// size tables by the bound, so a module this large is refused rather than
/// grown further.
const max_bound: u32 = 1 << 24;

/// Index operands an access chain may carry before this walker stops reading
/// it. Xenia's deepest chains have four.
const max_chain_indices = 32;

pub const Refusal = enum {
    none,
    /// Not a SPIR-V module in this host's byte order.
    not_spirv,
    /// An instruction's word count runs past the end of the module, or a
    /// section the walker relies on is missing.
    malformed,
    /// The module's id bound leaves no room for the clamps.
    id_space,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .none => "none",
            .not_spirv => "not-spirv",
            .malformed => "malformed-instruction-stream",
            .id_space => "id-space-exhausted",
        };
    }
};

pub const Stats = struct {
    /// Access chains inside function bodies.
    access_chains: u32 = 0,
    /// Indices into a storage buffer's run-time array, clamped to the bound
    /// descriptor range.
    runtime_array_clamps: u32 = 0,
    /// Indices into an array with a constant length.
    fixed_array_clamps: u32 = 0,
    /// Dynamic vector component or matrix column indices.
    component_clamps: u32 = 0,
    /// `OpArrayLength` results computed once at a function's entry.
    hoisted_lengths: u32 = 0,
    /// Dynamic indices this pass could not clamp (a spec-constant array
    /// length, a non-32-bit index, an unreadable base). Should read zero.
    unclamped_dynamic_indices: u32 = 0,
    /// Dynamic indices into shader inputs or outputs, left alone by design.
    interface_indices: u32 = 0,
    uniform_zero_loads: u32 = 0,

    pub fn clamps(self: Stats) u32 {
        return self.runtime_array_clamps + self.fixed_array_clamps + self.component_clamps;
    }

    pub fn add(self: *Stats, other: Stats) void {
        self.access_chains +|= other.access_chains;
        self.runtime_array_clamps +|= other.runtime_array_clamps;
        self.fixed_array_clamps +|= other.fixed_array_clamps;
        self.component_clamps +|= other.component_clamps;
        self.hoisted_lengths +|= other.hoisted_lengths;
        self.unclamped_dynamic_indices +|= other.unclamped_dynamic_indices;
        self.interface_indices +|= other.interface_indices;
        self.uniform_zero_loads +|= other.uniform_zero_loads;
    }
};

pub const Result = struct {
    /// The hardened module, owned by the caller. Empty when the module needed
    /// no clamp or was refused; the original words are then the module.
    words: []u32 = &.{},
    refusal: Refusal = .none,
    stats: Stats = .{},

    pub fn changed(self: Result) bool {
        return self.words.len != 0;
    }
};

// -- SPIR-V opcodes and enumerants -------------------------------------------

const op_line: u16 = 8;
const op_ext_inst_import: u16 = 11;
const op_ext_inst: u16 = 12;
const op_memory_model: u16 = 14;
const op_type_int: u16 = 21;
const op_type_bool: u16 = 20;
const op_type_float: u16 = 22;
const op_type_vector: u16 = 23;
const op_type_matrix: u16 = 24;
const op_type_array: u16 = 28;
const op_type_runtime_array: u16 = 29;
const op_type_struct: u16 = 30;
const op_type_pointer: u16 = 32;
const op_constant: u16 = 43;
const op_constant_null: u16 = 46;
const op_function: u16 = 54;
const op_function_end: u16 = 56;
const op_variable: u16 = 59;
const op_load: u16 = 61;
const op_composite_construct: u16 = 80;
const op_copy_object: u16 = 83;
const op_access_chain: u16 = 65;
const op_in_bounds_access_chain: u16 = 66;
const op_array_length: u16 = 68;
const op_decorate: u16 = 71;
const op_bitcast: u16 = 124;
const op_i_sub: u16 = 130;
const op_logical_and: u16 = 167;
const op_select: u16 = 169;
const op_u_less_than_equal: u16 = 178;
const op_label: u16 = 248;
const op_no_line: u16 = 317;

const storage_class_input: u32 = 1;
const storage_class_uniform: u32 = 2;
const storage_class_output: u32 = 3;
const storage_class_storage_buffer: u32 = 12;

const decoration_block: u32 = 2;
const decoration_buffer_block: u32 = 3;

const glsl_umin: u32 = 38;
const glsl_umax: u32 = 41;

/// "GLSL.std.450", NUL-terminated, as SPIR-V string words.
const glsl_std_450_name = [_]u32{ 0x4C53_4C47, 0x6474_732E, 0x3035_342E, 0 };

/// Every core opcode whose first two operands are a result type and a result
/// id, from `SpvHasResultAndType` in the SPIR-V 1.6 headers (unified1
/// revision 1). The walker reads the type of every value from this, so an
/// index's type is known exactly, not guessed from its opcode's name.
const result_type_ranges = [_][2]u16{
    .{ 1, 1 },       .{ 12, 12 },     .{ 41, 46 },     .{ 48, 52 },     .{ 54, 55 },     .{ 57, 57 },
    .{ 59, 61 },     .{ 65, 70 },     .{ 77, 84 },     .{ 86, 98 },     .{ 100, 107 },   .{ 109, 124 },
    .{ 126, 152 },   .{ 154, 191 },   .{ 194, 205 },   .{ 207, 215 },   .{ 227, 227 },   .{ 229, 242 },
    .{ 245, 245 },   .{ 259, 259 },   .{ 261, 271 },   .{ 274, 279 },   .{ 282, 286 },   .{ 291, 296 },
    .{ 299, 300 },   .{ 303, 316 },   .{ 318, 318 },   .{ 320, 321 },   .{ 323, 326 },   .{ 328, 328 },
    .{ 333, 366 },   .{ 400, 403 },   .{ 4421, 4422 }, .{ 4428, 4432 }, .{ 4447, 4447 }, .{ 4450, 4455 },
    .{ 4477, 4477 }, .{ 4479, 4479 }, .{ 5000, 5007 }, .{ 5011, 5012 }, .{ 5056, 5056 }, .{ 5283, 5283 },
    .{ 5296, 5296 }, .{ 5334, 5334 }, .{ 5359, 5359 }, .{ 5361, 5362 }, .{ 5381, 5381 }, .{ 5391, 5396 },
    .{ 5571, 5575 }, .{ 5577, 5577 }, .{ 5580, 5580 }, .{ 5585, 5598 }, .{ 5600, 5601 }, .{ 5609, 5611 },
    .{ 5614, 5615 }, .{ 5631, 5631 }, .{ 5699, 5699 }, .{ 5713, 5816 }, .{ 5818, 5819 }, .{ 5840, 5843 },
    .{ 5846, 5882 }, .{ 5923, 5934 }, .{ 5938, 5938 }, .{ 5946, 5947 }, .{ 5949, 5949 }, .{ 6016, 6032 },
    .{ 6035, 6035 }, .{ 6401, 6408 },
};

fn hasResultType(opcode: u16) bool {
    for (result_type_ranges) |range| {
        if (opcode < range[0]) return false;
        if (opcode <= range[1]) return true;
    }
    return false;
}

fn opcodeOf(word: u32) u16 {
    return @truncate(word);
}

fn wordCountOf(word: u32) u16 {
    return @truncate(word >> 16);
}

fn instructionWord(opcode: u16, count: u16) u32 {
    return (@as(u32, count) << 16) | opcode;
}

// -- Module facts ------------------------------------------------------------

const Kind = enum(u8) { unknown, int, vector, matrix, array, runtime_array, structure, pointer };

const TypeInfo = struct {
    kind: Kind = .unknown,
    /// int: width; vector/matrix/array/runtime_array: element type;
    /// structure: first index into `members`; pointer: storage class.
    a: u32 = 0,
    /// int: signedness; vector/matrix: count; array: length id;
    /// structure: member count; pointer: pointee type.
    b: u32 = 0,
};

const Facts = struct {
    types: []TypeInfo,
    value_type: []u32,
    constant: []u64,
    is_constant: std.DynamicBitSetUnmanaged,
    is_block: std.DynamicBitSetUnmanaged,
    is_uniform_block: std.DynamicBitSetUnmanaged,
    is_global_variable: std.DynamicBitSetUnmanaged,
    members: std.ArrayList(u32) = .empty,
    /// (value << 32 | type) of every 32-bit integer OpConstant, for reuse.
    constants_by_value: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// (storage class << 32 | pointee) of every pointer type, for reuse.
    pointers: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    uint_type: u32 = 0,
    bool_type: u32 = 0,
    glsl: u32 = 0,
    memory_model_offset: usize = 0,
    functions_offset: usize = 0,

    fn deinit(self: *Facts, allocator: std.mem.Allocator) void {
        allocator.free(self.types);
        allocator.free(self.value_type);
        allocator.free(self.constant);
        self.is_constant.deinit(allocator);
        self.is_block.deinit(allocator);
        self.is_uniform_block.deinit(allocator);
        self.is_global_variable.deinit(allocator);
        self.members.deinit(allocator);
        self.constants_by_value.deinit(allocator);
        self.pointers.deinit(allocator);
    }

    fn constantValue(self: *const Facts, id: u32) ?u64 {
        if (id >= self.types.len or !self.is_constant.isSet(id)) return null;
        return self.constant[id];
    }

    fn typeOf(self: *const Facts, id: u32) TypeInfo {
        if (id >= self.types.len) return .{};
        return self.types[id];
    }

    /// The type of a 32-bit integer value, or null when the value is not one.
    fn int32Type(self: *const Facts, value: u32) ?TypeInfo {
        if (value >= self.value_type.len) return null;
        const info = self.typeOf(self.value_type[value]);
        if (info.kind != .int or info.a != 32) return null;
        return info;
    }
};

fn scan(allocator: std.mem.Allocator, words: []const u32) error{ OutOfMemory, Malformed }!Facts {
    const bound = words[3];
    var facts = Facts{
        .types = try allocator.alloc(TypeInfo, bound),
        .value_type = try allocator.alloc(u32, bound),
        .constant = try allocator.alloc(u64, bound),
        .is_constant = try std.DynamicBitSetUnmanaged.initEmpty(allocator, bound),
        .is_block = try std.DynamicBitSetUnmanaged.initEmpty(allocator, bound),
        .is_uniform_block = try std.DynamicBitSetUnmanaged.initEmpty(allocator, bound),
        .is_global_variable = try std.DynamicBitSetUnmanaged.initEmpty(allocator, bound),
    };
    errdefer facts.deinit(allocator);
    @memset(facts.types, .{});
    @memset(facts.value_type, 0);
    @memset(facts.constant, 0);

    var offset: usize = 5;
    var in_function = false;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (count == 0 or offset + count > words.len) return error.Malformed;
        const opcode = opcodeOf(words[offset]);
        const operands = words[offset + 1 .. offset + count];
        if (hasResultType(opcode)) {
            if (operands.len < 2) return error.Malformed;
            if (operands[1] >= bound) return error.Malformed;
            facts.value_type[operands[1]] = operands[0];
        }
        switch (opcode) {
            op_ext_inst_import => if (operands.len == 5 and std.mem.eql(u32, operands[1..5], &glsl_std_450_name)) {
                facts.glsl = operands[0];
            },
            op_memory_model => facts.memory_model_offset = offset,
            op_decorate => if (operands.len >= 2 and operands[0] < bound and
                (operands[1] == decoration_block or operands[1] == decoration_buffer_block))
            {
                facts.is_block.set(operands[0]);
                if (operands[1] == decoration_block) facts.is_uniform_block.set(operands[0]);
            },
            op_type_bool => {
                if (operands.len < 1 or operands[0] >= bound) return error.Malformed;
                facts.bool_type = operands[0];
            },
            op_type_int => {
                if (operands.len < 3 or operands[0] >= bound) return error.Malformed;
                facts.types[operands[0]] = .{ .kind = .int, .a = operands[1], .b = operands[2] };
                if (operands[1] == 32 and operands[2] == 0 and facts.uint_type == 0) facts.uint_type = operands[0];
            },
            op_type_vector, op_type_matrix, op_type_array => {
                if (operands.len < 3 or operands[0] >= bound) return error.Malformed;
                facts.types[operands[0]] = .{
                    .kind = switch (opcode) {
                        op_type_vector => .vector,
                        op_type_matrix => .matrix,
                        else => .array,
                    },
                    .a = operands[1],
                    .b = operands[2],
                };
            },
            op_type_runtime_array => {
                if (operands.len < 2 or operands[0] >= bound) return error.Malformed;
                facts.types[operands[0]] = .{ .kind = .runtime_array, .a = operands[1] };
            },
            op_type_struct => {
                if (operands.len < 1 or operands[0] >= bound) return error.Malformed;
                facts.types[operands[0]] = .{
                    .kind = .structure,
                    .a = @intCast(facts.members.items.len),
                    .b = @intCast(operands.len - 1),
                };
                try facts.members.appendSlice(allocator, operands[1..]);
            },
            op_type_pointer => {
                if (operands.len < 3 or operands[0] >= bound) return error.Malformed;
                facts.types[operands[0]] = .{ .kind = .pointer, .a = operands[1], .b = operands[2] };
                const key = (@as(u64, operands[1]) << 32) | operands[2];
                const entry = try facts.pointers.getOrPut(allocator, key);
                if (!entry.found_existing) entry.value_ptr.* = operands[0];
            },
            op_constant => if (operands.len >= 3) {
                const info = facts.typeOf(operands[0]);
                if (info.kind == .int) {
                    var value: u64 = operands[2];
                    if (info.a == 64 and operands.len >= 4) value |= @as(u64, operands[3]) << 32;
                    facts.constant[operands[1]] = value;
                    facts.is_constant.set(operands[1]);
                    if (info.a == 32) {
                        const entry = try facts.constants_by_value.getOrPut(allocator, (value << 32) | operands[0]);
                        if (!entry.found_existing) entry.value_ptr.* = operands[1];
                    }
                }
            },
            op_constant_null => if (operands.len >= 2 and facts.typeOf(operands[0]).kind == .int) {
                facts.constant[operands[1]] = 0;
                facts.is_constant.set(operands[1]);
            },
            op_variable => if (!in_function and operands.len >= 2) facts.is_global_variable.set(operands[1]),
            op_function => {
                if (!in_function and facts.functions_offset == 0) facts.functions_offset = offset;
                in_function = true;
            },
            op_function_end => in_function = false,
            else => {},
        }
        offset += count;
    }
    if (offset != words.len or facts.memory_model_offset == 0) return error.Malformed;
    if (facts.functions_offset == 0) facts.functions_offset = words.len;
    return facts;
}

// -- Rewriting ---------------------------------------------------------------

const Hoist = struct {
    variable: u32,
    member: u32,
    length: u32,
    at_least_one: u32,
    max_index: u32,
};

const Rewriter = struct {
    allocator: std.mem.Allocator,
    words: []const u32,
    facts: *Facts,
    next_id: u32,
    /// Types and constants this pass declares, in declaration order.
    globals: std.ArrayList(u32) = .empty,
    /// The new GLSL.std.450 import, when the module had none.
    new_import: u32 = 0,
    body: std.ArrayList(u32) = .empty,
    /// Instructions emitted ahead of the access chain being rewritten.
    prefix: std.ArrayList(u32) = .empty,
    hoists: std.ArrayList(Hoist) = .empty,
    uniform_conditions: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    nulls: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    bool_vectors: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    stats: Stats = .{},

    fn deinit(self: *Rewriter) void {
        self.globals.deinit(self.allocator);
        self.body.deinit(self.allocator);
        self.prefix.deinit(self.allocator);
        self.hoists.deinit(self.allocator);
        self.uniform_conditions.deinit(self.allocator);
        self.nulls.deinit(self.allocator);
        self.bool_vectors.deinit(self.allocator);
    }

    fn newId(self: *Rewriter) error{IdSpace}!u32 {
        if (self.next_id >= max_bound) return error.IdSpace;
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    fn emitInto(self: *Rewriter, list: *std.ArrayList(u32), opcode: u16, operands: []const u32) error{OutOfMemory}!void {
        try list.append(self.allocator, instructionWord(opcode, @intCast(operands.len + 1)));
        try list.appendSlice(self.allocator, operands);
    }

    fn glsl(self: *Rewriter) error{IdSpace}!u32 {
        if (self.facts.glsl == 0) {
            self.facts.glsl = try self.newId();
            self.new_import = self.facts.glsl;
        }
        return self.facts.glsl;
    }

    fn uintType(self: *Rewriter) error{ OutOfMemory, IdSpace }!u32 {
        if (self.facts.uint_type == 0) {
            const id = try self.newId();
            try self.emitInto(&self.globals, op_type_int, &.{ id, 32, 0 });
            self.facts.uint_type = id;
        }
        return self.facts.uint_type;
    }

    fn boolType(self: *Rewriter) error{ OutOfMemory, IdSpace }!u32 {
        if (self.facts.bool_type == 0) {
            self.facts.bool_type = try self.newId();
            try self.emitInto(&self.globals, op_type_bool, &.{self.facts.bool_type});
        }
        return self.facts.bool_type;
    }

    fn uniformCondition(self: *Rewriter, previous: u32, unsigned_index: u32, max_index: u32) error{ OutOfMemory, IdSpace }!u32 {
        // The clamp's unsigned input is also the comparison's input. Negative
        // signed indices therefore fail the check rather than reading c[255].
        const condition = try self.newId();
        const boolean = try self.boolType();
        try self.emitInto(&self.prefix, op_u_less_than_equal, &.{ boolean, condition, unsigned_index, max_index });
        if (previous == 0) return condition;
        const combined = try self.newId();
        try self.emitInto(&self.prefix, op_logical_and, &.{ boolean, combined, previous, condition });
        return combined;
    }

    fn uniformLoad(self: *Rewriter, instruction: []const u32, scalar_condition: u32) error{ OutOfMemory, IdSpace }!void {
        const value_type = instruction[1];
        const raw_value = try self.newId();
        var condition = scalar_condition;
        const info = self.facts.typeOf(value_type);
        if (info.kind == .vector) {
            // SPIR-V 1.0 requires a vector condition for a vector OpSelect.
            const entry = try self.bool_vectors.getOrPut(self.allocator, info.b);
            if (!entry.found_existing) {
                const boolean = try self.boolType();
                entry.value_ptr.* = 0;
                for (self.facts.types, 0..) |candidate, id| {
                    if (candidate.kind == .vector and candidate.a == boolean and candidate.b == info.b) {
                        entry.value_ptr.* = @intCast(id);
                        break;
                    }
                }
                if (entry.value_ptr.* == 0) {
                    entry.value_ptr.* = try self.newId();
                    try self.emitInto(&self.globals, op_type_vector, &.{ entry.value_ptr.*, boolean, info.b });
                }
            }
            condition = try self.newId();
            try self.body.appendSlice(self.allocator, &.{ instructionWord(op_composite_construct, @intCast(3 + info.b)), entry.value_ptr.*, condition });
            for (0..info.b) |_| try self.body.append(self.allocator, scalar_condition);
        }
        const zero = try self.nulls.getOrPut(self.allocator, value_type);
        if (!zero.found_existing) {
            zero.value_ptr.* = try self.newId();
            try self.emitInto(&self.globals, op_constant_null, &.{ value_type, zero.value_ptr.* });
        }
        // Keep the original load's memory operands and its result id's uses.
        try self.body.appendSlice(self.allocator, &.{ instruction[0], value_type, raw_value });
        try self.body.appendSlice(self.allocator, instruction[3..]);
        try self.emitInto(&self.body, op_select, &.{ value_type, instruction[2], condition, raw_value, zero.value_ptr.* });
        self.stats.uniform_zero_loads += 1;
    }

    fn uintConstant(self: *Rewriter, value: u32) error{ OutOfMemory, IdSpace }!u32 {
        const uint = try self.uintType();
        const entry = try self.facts.constants_by_value.getOrPut(self.allocator, (@as(u64, value) << 32) | uint);
        if (!entry.found_existing) {
            const id = try self.newId();
            try self.emitInto(&self.globals, op_constant, &.{ uint, id, value });
            entry.value_ptr.* = id;
        }
        return entry.value_ptr.*;
    }

    fn pointerType(self: *Rewriter, storage_class: u32, pointee: u32) error{ OutOfMemory, IdSpace }!u32 {
        const entry = try self.facts.pointers.getOrPut(self.allocator, (@as(u64, storage_class) << 32) | pointee);
        if (!entry.found_existing) {
            const id = try self.newId();
            try self.emitInto(&self.globals, op_type_pointer, &.{ id, storage_class, pointee });
            entry.value_ptr.* = id;
        }
        return entry.value_ptr.*;
    }

    /// `index` as an unsigned 32-bit value, clamped to `max_index`; null when
    /// the index is not a 32-bit integer.
    const Clamp = struct { index: u32, unsigned_index: u32 };

    fn clamp(self: *Rewriter, index: u32, max_index: u32) error{ OutOfMemory, IdSpace }!?Clamp {
        const info = self.facts.int32Type(index) orelse return null;
        const uint = try self.uintType();
        var unsigned_index = index;
        if (info.b != 0) {
            unsigned_index = try self.newId();
            try self.emitInto(&self.prefix, op_bitcast, &.{ uint, unsigned_index, index });
        }
        const clamped = try self.newId();
        try self.emitInto(&self.prefix, op_ext_inst, &.{ uint, clamped, try self.glsl(), glsl_umin, unsigned_index, max_index });
        return .{ .index = clamped, .unsigned_index = unsigned_index };
    }

    /// `max(len, 1) - 1` for the run-time array that is member `member` of
    /// the block `structure_pointer` points at, emitted into `list`.
    fn emitMaxIndex(self: *Rewriter, list: *std.ArrayList(u32), structure_pointer: u32, member: u32, ids: [3]u32) error{ OutOfMemory, IdSpace }!void {
        const uint = try self.uintType();
        const one = try self.uintConstant(1);
        try self.emitInto(list, op_array_length, &.{ uint, ids[0], structure_pointer, member });
        try self.emitInto(list, op_ext_inst, &.{ uint, ids[1], try self.glsl(), glsl_umax, ids[0], one });
        try self.emitInto(list, op_i_sub, &.{ uint, ids[2], ids[1], one });
    }

    /// The hoisted maximum index of a buffer variable's run-time array,
    /// computed once at the top of the current function.
    fn hoistedMaxIndex(self: *Rewriter, variable: u32, member: u32) error{ OutOfMemory, IdSpace }!u32 {
        for (self.hoists.items) |hoist| {
            if (hoist.variable == variable and hoist.member == member) return hoist.max_index;
        }
        const hoist = Hoist{
            .variable = variable,
            .member = member,
            .length = try self.newId(),
            .at_least_one = try self.newId(),
            .max_index = try self.newId(),
        };
        try self.hoists.append(self.allocator, hoist);
        self.stats.hoisted_lengths += 1;
        return hoist.max_index;
    }

    fn countUnclamped(self: *Rewriter, indices: []const u32) void {
        for (indices) |index| {
            if (self.facts.constantValue(index) == null) self.stats.unclamped_dynamic_indices += 1;
        }
    }

    fn accessChain(self: *Rewriter, instruction: []const u32) error{ OutOfMemory, IdSpace }!void {
        self.stats.access_chains += 1;
        const result_type = instruction[1];
        const result = instruction[2];
        const base = instruction[3];
        const indices = instruction[4..];
        if (indices.len == 0 or indices.len > max_chain_indices) {
            self.countUnclamped(indices);
            return self.body.appendSlice(self.allocator, instruction);
        }
        const facts = self.facts;
        const base_pointer = if (base < facts.value_type.len) facts.typeOf(facts.value_type[base]) else TypeInfo{};
        if (base_pointer.kind != .pointer) {
            self.countUnclamped(indices);
            return self.body.appendSlice(self.allocator, instruction);
        }
        const storage_class = base_pointer.a;
        const interface = storage_class == storage_class_input or storage_class == storage_class_output;
        var uniform_block = false;
        var uniform_condition = self.uniform_conditions.get(base) orelse 0;

        var rewritten: [max_chain_indices]u32 = undefined;
        @memcpy(rewritten[0..indices.len], indices);
        self.prefix.clearRetainingCapacity();
        var changed = false;
        var current = base_pointer.b;
        var parent_structure: u32 = 0;
        var parent_member: u32 = 0;
        var level: usize = 0;
        walk: while (level < indices.len) : (level += 1) {
            const index = indices[level];
            const constant = facts.constantValue(index);
            const info = facts.typeOf(current);
            switch (info.kind) {
                .structure => {
                    if (storage_class == storage_class_uniform and facts.is_uniform_block.isSet(current)) uniform_block = true;
                    const member = constant orelse break :walk;
                    if (member >= info.b) break :walk;
                    parent_structure = current;
                    parent_member = @intCast(member);
                    current = facts.members.items[info.a + parent_member];
                },
                .array, .vector, .matrix => {
                    const length: ?u64 = if (info.kind == .array) facts.constantValue(info.b) else info.b;
                    current = info.a;
                    if (constant) |value| {
                        if (length) |n| {
                            if (value < n) continue;
                        }
                    }
                    if (interface) {
                        if (constant == null) self.stats.interface_indices += 1;
                        continue;
                    }
                    const n = length orelse {
                        self.stats.unclamped_dynamic_indices += 1;
                        continue;
                    };
                    if (n == 0 or n - 1 > std.math.maxInt(u32)) {
                        self.stats.unclamped_dynamic_indices += 1;
                        continue;
                    }
                    const max_index = try self.uintConstant(@intCast(n - 1));
                    if (try self.clamp(index, max_index)) |clamped| {
                        rewritten[level] = clamped.index;
                        if (uniform_block or uniform_condition != 0) uniform_condition = try self.uniformCondition(uniform_condition, clamped.unsigned_index, max_index);
                        changed = true;
                        if (info.kind == .array) self.stats.fixed_array_clamps += 1 else self.stats.component_clamps += 1;
                    } else self.stats.unclamped_dynamic_indices += 1;
                },
                .runtime_array => {
                    current = info.a;
                    if (constant) |value| {
                        if (value == 0) continue;
                    }
                    const buffer_class = storage_class == storage_class_storage_buffer or storage_class == storage_class_uniform;
                    const last_member = level >= 1 and parent_structure != 0 and
                        parent_member + 1 == facts.typeOf(parent_structure).b and
                        facts.is_block.isSet(parent_structure);
                    if (!buffer_class or !last_member or facts.int32Type(index) == null) {
                        self.stats.unclamped_dynamic_indices += 1;
                        continue;
                    }
                    const max_index = blk: {
                        if (level == 1 and base < facts.is_global_variable.bit_length and facts.is_global_variable.isSet(base)) {
                            break :blk try self.hoistedMaxIndex(base, parent_member);
                        }
                        // An array of buffer descriptors, or a block reached
                        // through another pointer: point at the block itself,
                        // with the indices already clamped, and measure it here.
                        var structure_pointer = base;
                        if (level > 1) {
                            structure_pointer = try self.newId();
                            const pointer_type = try self.pointerType(storage_class, parent_structure);
                            try self.prefix.append(self.allocator, instructionWord(op_access_chain, @intCast(4 + level - 1)));
                            try self.prefix.appendSlice(self.allocator, &.{ pointer_type, structure_pointer, base });
                            try self.prefix.appendSlice(self.allocator, rewritten[0 .. level - 1]);
                        }
                        const ids = [3]u32{ try self.newId(), try self.newId(), try self.newId() };
                        try self.emitMaxIndex(&self.prefix, structure_pointer, parent_member, ids);
                        break :blk ids[2];
                    };
                    if (try self.clamp(index, max_index)) |clamped| {
                        rewritten[level] = clamped.index;
                        changed = true;
                        self.stats.runtime_array_clamps += 1;
                    } else self.stats.unclamped_dynamic_indices += 1;
                },
                else => break :walk,
            }
        }
        // The walk stopped on a type it does not index into (a malformed
        // chain); whatever dynamic indices remain stay as they were.
        if (level < indices.len) self.countUnclamped(indices[level..]);

        if (uniform_condition != 0) try self.uniform_conditions.put(self.allocator, result, uniform_condition);

        if (!changed) {
            self.prefix.clearRetainingCapacity();
            return self.body.appendSlice(self.allocator, instruction);
        }
        try self.body.appendSlice(self.allocator, self.prefix.items);
        try self.body.append(self.allocator, instruction[0]);
        try self.body.appendSlice(self.allocator, &.{ result_type, result, base });
        try self.body.appendSlice(self.allocator, rewritten[0..indices.len]);
    }

    /// Rewrite one function, `words[start..end]`, starting at its OpFunction.
    fn function(self: *Rewriter, start: usize, end: usize) error{ OutOfMemory, IdSpace }!void {
        self.hoists.clearRetainingCapacity();
        self.uniform_conditions.clearRetainingCapacity();
        var offset = start;
        var entry_insert: ?usize = null;
        var seen_label = false;
        while (offset < end) {
            const count = wordCountOf(self.words[offset]);
            const opcode = opcodeOf(self.words[offset]);
            const instruction = self.words[offset .. offset + count];
            if (seen_label and entry_insert == null and opcode != op_variable and opcode != op_line and opcode != op_no_line) {
                entry_insert = self.body.items.len;
            }
            if (opcode == op_label and !seen_label) seen_label = true;
            if (opcode == op_access_chain or opcode == op_in_bounds_access_chain) {
                if (count < 4) {
                    try self.body.appendSlice(self.allocator, instruction);
                } else {
                    try self.accessChain(instruction);
                }
            } else if (opcode == op_load and count >= 4 and self.uniform_conditions.contains(instruction[3])) {
                const kind = self.facts.typeOf(instruction[1]).kind;
                // OpSelect cannot select aggregates in SPIR-V 1.0. Xenia's
                // constant-register reads are vectors or scalar components.
                if (kind == .matrix or kind == .array or kind == .structure or kind == .pointer) {
                    try self.body.appendSlice(self.allocator, instruction);
                } else try self.uniformLoad(instruction, self.uniform_conditions.get(instruction[3]).?);
            } else if (opcode == op_copy_object and count == 4 and self.uniform_conditions.contains(instruction[3])) {
                try self.uniform_conditions.put(self.allocator, instruction[2], self.uniform_conditions.get(instruction[3]).?);
                try self.body.appendSlice(self.allocator, instruction);
            } else {
                try self.body.appendSlice(self.allocator, instruction);
            }
            offset += count;
        }
        if (self.hoists.items.len == 0) return;
        var block: std.ArrayList(u32) = .empty;
        defer block.deinit(self.allocator);
        for (self.hoists.items) |hoist| {
            try self.emitMaxIndex(&block, hoist.variable, hoist.member, .{ hoist.length, hoist.at_least_one, hoist.max_index });
        }
        // A function with access chains has an entry block, and an access
        // chain is never one of its leading variables, so the insertion point
        // was always passed.
        try self.body.insertSlice(self.allocator, entry_insert.?, block.items);
    }
};

/// Clamp every dynamically indexed array, vector and matrix access in a
/// SPIR-V module into its bounds. See the file comment.
pub fn harden(allocator: std.mem.Allocator, words: []const u32) error{OutOfMemory}!Result {
    if (words.len < 5 or words[0] != magic) return .{ .refusal = .not_spirv };
    const bound = words[3];
    if (bound == 0 or bound >= max_bound) return .{ .refusal = .id_space };
    var facts = scan(allocator, words) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Malformed => return .{ .refusal = .malformed },
    };
    defer facts.deinit(allocator);

    var rewriter = Rewriter{ .allocator = allocator, .words = words, .facts = &facts, .next_id = bound };
    defer rewriter.deinit();

    var offset = facts.functions_offset;
    var function_start: usize = 0;
    var in_function = false;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        const opcode = opcodeOf(words[offset]);
        if (opcode == op_function and !in_function) {
            function_start = offset;
            in_function = true;
        } else if (opcode == op_function_end and in_function) {
            rewriter.function(function_start, offset + count) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.IdSpace => return .{ .refusal = .id_space },
            };
            in_function = false;
        } else if (!in_function) {
            // Nothing but functions follows the first OpFunction.
            return .{ .refusal = .malformed };
        }
        offset += count;
    }
    if (in_function) return .{ .refusal = .malformed };
    if (rewriter.stats.clamps() == 0) return .{ .stats = rewriter.stats };

    var out: std.ArrayList(u32) = .empty;
    errdefer out.deinit(allocator);
    const import_words: usize = if (rewriter.new_import != 0) 2 + glsl_std_450_name.len else 0;
    try out.ensureTotalCapacity(allocator, words.len + import_words + rewriter.globals.items.len + rewriter.body.items.len);
    try out.appendSlice(allocator, words[0..5]);
    out.items[3] = rewriter.next_id;
    try out.appendSlice(allocator, words[5..facts.memory_model_offset]);
    if (rewriter.new_import != 0) {
        try out.append(allocator, instructionWord(op_ext_inst_import, @intCast(import_words)));
        try out.append(allocator, rewriter.new_import);
        try out.appendSlice(allocator, &glsl_std_450_name);
    }
    try out.appendSlice(allocator, words[facts.memory_model_offset..facts.functions_offset]);
    try out.appendSlice(allocator, rewriter.globals.items);
    try out.appendSlice(allocator, rewriter.body.items);
    return .{ .words = try out.toOwnedSlice(allocator), .stats = rewriter.stats };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

const op_capability: u16 = 17;
const op_entry_point: u16 = 15;
const op_type_void: u16 = 19;
const op_type_function: u16 = 33;
const op_store: u16 = 62;
const op_i_add: u16 = 128;
const op_return: u16 = 253;
const op_function_parameter: u16 = 55;
const storage_class_function: u32 = 7;

/// A hand-assembled module: ids are chosen by the test, so every check can
/// name exactly the instruction it expects.
const Asm = struct {
    words: std.ArrayList(u32) = .empty,

    fn init(bound: u32) !Asm {
        var self = Asm{};
        try self.words.appendSlice(testing.allocator, &.{ magic, 0x0001_0300, 0, bound, 0 });
        return self;
    }

    fn deinit(self: *Asm) void {
        self.words.deinit(testing.allocator);
    }

    fn op(self: *Asm, opcode: u16, operands: []const u32) !void {
        try self.words.append(testing.allocator, instructionWord(opcode, @intCast(operands.len + 1)));
        try self.words.appendSlice(testing.allocator, operands);
    }

    fn preamble(self: *Asm, with_glsl: bool, glsl_id: u32) !void {
        try self.op(op_capability, &.{1});
        if (with_glsl) try self.op(op_ext_inst_import, &.{ glsl_id, 0x4C53_4C47, 0x6474_732E, 0x3035_342E, 0 });
        try self.op(op_memory_model, &.{ 0, 1 });
        try self.op(op_entry_point, &.{ 5, 1, 0x6E69_616D, 0 });
    }
};

const Instruction = struct { opcode: u16, operands: []const u32, offset: usize };

fn instructions(words: []const u32, buffer: []Instruction) []Instruction {
    var count: usize = 0;
    var offset: usize = 5;
    while (offset < words.len and count < buffer.len) {
        const n = wordCountOf(words[offset]);
        buffer[count] = .{ .opcode = opcodeOf(words[offset]), .operands = words[offset + 1 .. offset + n], .offset = offset };
        count += 1;
        offset += n;
    }
    return buffer[0..count];
}

fn find(list: []const Instruction, opcode: u16, result_at: usize, result: u32) ?Instruction {
    for (list) |instruction| {
        if (instruction.opcode == opcode and instruction.operands.len > result_at and instruction.operands[result_at] == result) return instruction;
    }
    return null;
}

fn firstIndexOf(list: []const Instruction, opcode: u16) ?usize {
    for (list, 0..) |instruction, index| if (instruction.opcode == opcode) return index;
    return null;
}

fn walkable(words: []const u32) bool {
    if (words.len < 5 or words[0] != magic) return false;
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (count == 0 or offset + count > words.len) return false;
        offset += count;
    }
    return true;
}

// Ids shared by the storage-buffer modules below.
const id_main = 1;
const id_void = 2;
const id_fn = 3;
const id_int = 4;
const id_runtime = 5;
const id_block = 6;
const id_ptr_block = 7;
const id_ptr_int = 8;
const id_buffer = 9;
const id_zero = 10;
const id_seven = 11;
const id_label = 12;
const id_dynamic = 13;
const id_chain = 14;
const id_glsl = 15;
const id_chain_2 = 16;
const id_bound = 20;

/// Xenia's FSI EDRAM shape: `buffer XeEdram { uint edram[]; }` written at an
/// index computed in the shader.
fn edramModule(with_glsl: bool, signed_index: bool, extra_chain: bool) !Asm {
    var module = try Asm.init(id_bound);
    try module.preamble(with_glsl, id_glsl);
    try module.op(op_decorate, &.{ id_block, decoration_block });
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, @intFromBool(signed_index) });
    try module.op(op_type_runtime_array, &.{ id_runtime, id_int });
    try module.op(op_type_struct, &.{ id_block, id_runtime });
    try module.op(op_type_pointer, &.{ id_ptr_block, storage_class_storage_buffer, id_block });
    try module.op(op_type_pointer, &.{ id_ptr_int, storage_class_storage_buffer, id_int });
    try module.op(op_variable, &.{ id_ptr_block, id_buffer, storage_class_storage_buffer });
    try module.op(op_constant, &.{ id_int, id_zero, 0 });
    try module.op(op_constant, &.{ id_int, id_seven, 7 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    try module.op(op_i_add, &.{ id_int, id_dynamic, id_seven, id_seven });
    try module.op(op_access_chain, &.{ id_ptr_int, id_chain, id_buffer, id_zero, id_dynamic });
    try module.op(op_store, &.{ id_chain, id_seven });
    if (extra_chain) {
        try module.op(op_access_chain, &.{ id_ptr_int, id_chain_2, id_buffer, id_zero, id_dynamic });
        try module.op(op_store, &.{ id_chain_2, id_seven });
    }
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});
    return module;
}

test "a storage buffer index is clamped to the bound range, measured once per function" {
    var module = try edramModule(true, false, true);
    defer module.deinit();
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(result.changed());
    try testing.expect(walkable(result.words));
    try testing.expectEqual(@as(u32, 2), result.stats.runtime_array_clamps);
    try testing.expectEqual(@as(u32, 1), result.stats.hoisted_lengths);
    try testing.expectEqual(@as(u32, 0), result.stats.unclamped_dynamic_indices);
    try testing.expect(result.words[3] > id_bound);

    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    // The length is measured right after the entry label, before the index
    // it bounds is even computed.
    const label = firstIndexOf(list, op_label).?;
    try testing.expectEqual(op_array_length, list[label + 1].opcode);
    try testing.expectEqual(@as(u32, id_buffer), list[label + 1].operands[2]);
    try testing.expectEqual(@as(u32, 0), list[label + 1].operands[3]);
    try testing.expectEqual(op_ext_inst, list[label + 2].opcode);
    try testing.expectEqual(glsl_umax, list[label + 2].operands[3]);
    try testing.expectEqual(op_i_sub, list[label + 3].opcode);
    const max_index = list[label + 3].operands[1];

    // Each chain now indexes with min(index, max_index); the struct member
    // index stays the constant it was.
    for ([_]u32{ id_chain, id_chain_2 }) |chain_id| {
        const chain = find(list, op_access_chain, 1, chain_id).?;
        try testing.expectEqual(@as(u32, id_buffer), chain.operands[2]);
        try testing.expectEqual(@as(u32, id_zero), chain.operands[3]);
        const clamp = find(list, op_ext_inst, 1, chain.operands[4]).?;
        try testing.expectEqual(@as(u32, id_glsl), clamp.operands[2]);
        try testing.expectEqual(glsl_umin, clamp.operands[3]);
        try testing.expectEqual(@as(u32, id_dynamic), clamp.operands[4]);
        try testing.expectEqual(max_index, clamp.operands[5]);
    }
}

test "a signed index is reinterpreted as unsigned, so a negative one clamps to the last element" {
    var module = try edramModule(true, true, false);
    defer module.deinit();
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(result.changed());
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    const chain = find(list, op_access_chain, 1, id_chain).?;
    const clamp = find(list, op_ext_inst, 1, chain.operands[4]).?;
    const cast = find(list, op_bitcast, 1, clamp.operands[4]).?;
    try testing.expectEqual(@as(u32, id_dynamic), cast.operands[2]);
    // The module had only a signed int; the unsigned type the clamp needs is
    // declared once, ahead of the constant 1 that uses it.
    const uint_decl = firstIndexOf(list, op_type_int).?;
    var unsigned_types: u32 = 0;
    for (list) |instruction| {
        if (instruction.opcode == op_type_int and instruction.operands[1] == 32 and instruction.operands[2] == 0) unsigned_types += 1;
    }
    try testing.expectEqual(@as(u32, 1), unsigned_types);
    try testing.expect(uint_decl < firstIndexOf(list, op_function).?);
    try testing.expectEqual(cast.operands[0], find(list, op_array_length, 1, list[firstIndexOf(list, op_label).? + 1].operands[1]).?.operands[0]);
}

test "a module without GLSL.std.450 gains the import ahead of its memory model" {
    var module = try edramModule(false, false, false);
    defer module.deinit();
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(result.changed());
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    const import_index = firstIndexOf(list, op_ext_inst_import).?;
    try testing.expectEqual(import_index + 1, firstIndexOf(list, op_memory_model).?);
    try testing.expectEqualSlices(u32, &glsl_std_450_name, list[import_index].operands[1..]);
    const chain = find(list, op_access_chain, 1, id_chain).?;
    const clamp = find(list, op_ext_inst, 1, chain.operands[4]).?;
    try testing.expectEqual(list[import_index].operands[0], clamp.operands[2]);
}

test "constant in-bounds indices leave a module untouched" {
    var module = try Asm.init(id_bound);
    defer module.deinit();
    try module.preamble(true, id_glsl);
    try module.op(op_decorate, &.{ id_block, decoration_block });
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, 0 });
    try module.op(op_type_runtime_array, &.{ id_runtime, id_int });
    try module.op(op_type_struct, &.{ id_block, id_runtime });
    try module.op(op_type_pointer, &.{ id_ptr_block, storage_class_storage_buffer, id_block });
    try module.op(op_type_pointer, &.{ id_ptr_int, storage_class_storage_buffer, id_int });
    try module.op(op_variable, &.{ id_ptr_block, id_buffer, storage_class_storage_buffer });
    try module.op(op_constant, &.{ id_int, id_zero, 0 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    // Element 0 of a bound storage buffer always exists.
    try module.op(op_access_chain, &.{ id_ptr_int, id_chain, id_buffer, id_zero, id_zero });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(!result.changed());
    try testing.expectEqual(@as(u32, 1), result.stats.access_chains);
    try testing.expectEqual(@as(u32, 0), result.stats.clamps());
}

test "Xenia's relative constant load uses a bounded pointer and selects zero outside its uniform array" {
    // float_constants[a0 + 16] with `vec4 float_constants[256]`.
    const id_float = 21;
    const id_vec4 = 22;
    const id_c256 = 23;
    const id_array = 24;
    const id_c255 = 25;
    const id_ptr_vec4 = 26;
    var module = try Asm.init(40);
    defer module.deinit();
    try module.preamble(true, id_glsl);
    try module.op(op_decorate, &.{ id_block, decoration_block });
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, 0 });
    try module.op(op_type_float, &.{ id_float, 32 });
    try module.op(op_type_vector, &.{ id_vec4, id_float, 4 });
    try module.op(op_type_bool, &.{30});
    try module.op(op_type_vector, &.{ 31, 30, 4 });
    try module.op(op_constant, &.{ id_int, id_c256, 256 });
    try module.op(op_constant, &.{ id_int, id_c255, 255 });
    try module.op(op_type_array, &.{ id_array, id_vec4, id_c256 });
    try module.op(op_type_struct, &.{ id_block, id_array });
    try module.op(op_type_pointer, &.{ id_ptr_block, storage_class_uniform, id_block });
    try module.op(op_type_pointer, &.{ id_ptr_vec4, storage_class_uniform, id_vec4 });
    try module.op(op_variable, &.{ id_ptr_block, id_buffer, storage_class_uniform });
    try module.op(op_constant, &.{ id_int, id_zero, 0 });
    try module.op(op_constant, &.{ id_int, id_seven, 16 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    try module.op(op_i_add, &.{ id_int, id_dynamic, id_seven, id_seven });
    try module.op(op_access_chain, &.{ id_ptr_vec4, id_chain, id_buffer, id_zero, id_dynamic });
    try module.op(op_load, &.{ id_vec4, 27, id_chain });
    try module.op(op_copy_object, &.{ id_ptr_vec4, 28, id_chain });
    try module.op(op_load, &.{ id_vec4, 29, 28 });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});
    const before_bound = module.words.items[3];

    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(result.changed());
    try testing.expectEqual(@as(u32, 1), result.stats.fixed_array_clamps);
    try testing.expectEqual(@as(u32, 0), result.stats.hoisted_lengths);
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    const chain = find(list, op_access_chain, 1, id_chain).?;
    const clamp = find(list, op_ext_inst, 1, chain.operands[4]).?;
    try testing.expectEqual(glsl_umin, clamp.operands[3]);
    try testing.expectEqual(@as(u32, id_c255), clamp.operands[5]);
    _ = before_bound;
    try testing.expectEqual(@as(u32, 2), result.stats.uniform_zero_loads);
    const select = find(list, op_select, 1, 27).?;
    const zero = find(list, op_constant_null, 1, select.operands[4]).?;
    try testing.expectEqual(@as(u32, id_vec4), zero.operands[0]);
    const loaded = find(list, op_load, 1, select.operands[3]).?;
    try testing.expectEqual(@as(u32, id_chain), loaded.operands[2]);
    // The valid predicate is based on the original index, never its clamp.
    const condition_vector = find(list, op_composite_construct, 1, select.operands[2]).?;
    try testing.expectEqual(@as(u32, 31), condition_vector.operands[0]);
    const valid = find(list, op_u_less_than_equal, 1, condition_vector.operands[2]).?;
    try testing.expectEqual(@as(u32, id_dynamic), valid.operands[2]);
    try testing.expectEqual(@as(u32, id_c255), valid.operands[3]);
    try testing.expect(find(list, op_select, 1, 29) != null);
    try testing.expectEqual(@as(?usize, null), firstIndexOf(list, op_array_length));
}

test "an array of buffer descriptors clamps the descriptor index and measures the selected block" {
    const id_c4 = 21;
    const id_blocks = 22;
    const id_ptr_blocks = 23;
    const id_binding = 24;
    var module = try Asm.init(40);
    defer module.deinit();
    try module.preamble(true, id_glsl);
    try module.op(op_decorate, &.{ id_block, decoration_block });
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, 0 });
    try module.op(op_constant, &.{ id_int, id_c4, 4 });
    try module.op(op_type_runtime_array, &.{ id_runtime, id_int });
    try module.op(op_type_struct, &.{ id_block, id_runtime });
    try module.op(op_type_array, &.{ id_blocks, id_block, id_c4 });
    try module.op(op_type_pointer, &.{ id_ptr_blocks, storage_class_storage_buffer, id_blocks });
    try module.op(op_type_pointer, &.{ id_ptr_int, storage_class_storage_buffer, id_int });
    try module.op(op_variable, &.{ id_ptr_blocks, id_buffer, storage_class_storage_buffer });
    try module.op(op_constant, &.{ id_int, id_zero, 0 });
    try module.op(op_constant, &.{ id_int, id_seven, 7 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    try module.op(op_i_add, &.{ id_int, id_dynamic, id_seven, id_seven });
    try module.op(op_i_add, &.{ id_int, id_binding, id_seven, id_zero });
    try module.op(op_access_chain, &.{ id_ptr_int, id_chain, id_buffer, id_binding, id_zero, id_dynamic });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});

    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(result.changed());
    try testing.expect(walkable(result.words));
    try testing.expectEqual(@as(u32, 1), result.stats.fixed_array_clamps);
    try testing.expectEqual(@as(u32, 1), result.stats.runtime_array_clamps);
    try testing.expectEqual(@as(u32, 0), result.stats.hoisted_lengths);
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    const chain = find(list, op_access_chain, 1, id_chain).?;
    const binding_clamp = find(list, op_ext_inst, 1, chain.operands[3]).?;
    try testing.expectEqual(@as(u32, id_binding), binding_clamp.operands[4]);
    // The block is selected with the clamped descriptor index, through a
    // pointer type this pass had to declare, and measured where it is used.
    const length = list[firstIndexOf(list, op_array_length).?];
    const block_pointer = find(list, op_access_chain, 1, length.operands[2]).?;
    try testing.expectEqual(@as(u32, id_buffer), block_pointer.operands[2]);
    try testing.expectEqual(binding_clamp.operands[1], block_pointer.operands[3]);
    const pointer_type = find(list, op_type_pointer, 0, block_pointer.operands[0]).?;
    try testing.expectEqual(storage_class_storage_buffer, pointer_type.operands[1]);
    try testing.expectEqual(@as(u32, id_block), pointer_type.operands[2]);
    try testing.expect(firstIndexOf(list, op_array_length).? > firstIndexOf(list, op_label).? + 2);
}

test "shader inputs and outputs keep their invocation-id indices" {
    const id_c32 = 21;
    const id_array = 22;
    const id_ptr_array = 23;
    const id_ptr_input_int = 24;
    var module = try Asm.init(40);
    defer module.deinit();
    try module.preamble(true, id_glsl);
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, 0 });
    try module.op(op_constant, &.{ id_int, id_c32, 32 });
    try module.op(op_type_array, &.{ id_array, id_int, id_c32 });
    try module.op(op_type_pointer, &.{ id_ptr_array, storage_class_input, id_array });
    try module.op(op_type_pointer, &.{ id_ptr_input_int, storage_class_input, id_int });
    try module.op(op_variable, &.{ id_ptr_array, id_buffer, storage_class_input });
    try module.op(op_constant, &.{ id_int, id_seven, 7 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    try module.op(op_i_add, &.{ id_int, id_dynamic, id_seven, id_seven });
    try module.op(op_access_chain, &.{ id_ptr_input_int, id_chain, id_buffer, id_dynamic });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(!result.changed());
    try testing.expectEqual(@as(u32, 1), result.stats.interface_indices);
    try testing.expectEqual(@as(u32, 0), result.stats.unclamped_dynamic_indices);
}

test "lengths are hoisted past a function's own variables, in every function that needs them" {
    const id_helper = 21;
    const id_helper_label = 22;
    const id_ptr_function_int = 23;
    const id_local = 24;
    const id_local_2 = 25;
    const id_helper_dynamic = 26;
    const id_helper_chain = 27;
    var module = try Asm.init(40);
    defer module.deinit();
    try module.preamble(true, id_glsl);
    try module.op(op_decorate, &.{ id_block, decoration_block });
    try module.op(op_type_void, &.{id_void});
    try module.op(op_type_function, &.{ id_fn, id_void });
    try module.op(op_type_int, &.{ id_int, 32, 0 });
    try module.op(op_type_runtime_array, &.{ id_runtime, id_int });
    try module.op(op_type_struct, &.{ id_block, id_runtime });
    try module.op(op_type_pointer, &.{ id_ptr_block, storage_class_storage_buffer, id_block });
    try module.op(op_type_pointer, &.{ id_ptr_int, storage_class_storage_buffer, id_int });
    try module.op(op_type_pointer, &.{ id_ptr_function_int, storage_class_function, id_int });
    try module.op(op_variable, &.{ id_ptr_block, id_buffer, storage_class_storage_buffer });
    try module.op(op_constant, &.{ id_int, id_zero, 0 });
    try module.op(op_constant, &.{ id_int, id_seven, 7 });
    try module.op(op_function, &.{ id_void, id_main, 0, id_fn });
    try module.op(op_label, &.{id_label});
    try module.op(op_variable, &.{ id_ptr_function_int, id_local, storage_class_function });
    try module.op(op_variable, &.{ id_ptr_function_int, id_local_2, storage_class_function });
    try module.op(op_load, &.{ id_int, id_dynamic, id_local });
    try module.op(op_access_chain, &.{ id_ptr_int, id_chain, id_buffer, id_zero, id_dynamic });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});
    try module.op(op_function, &.{ id_void, id_helper, 0, id_fn });
    try module.op(op_label, &.{id_helper_label});
    try module.op(op_i_add, &.{ id_int, id_helper_dynamic, id_seven, id_seven });
    try module.op(op_access_chain, &.{ id_ptr_int, id_helper_chain, id_buffer, id_zero, id_helper_dynamic });
    try module.op(op_return, &.{});
    try module.op(op_function_end, &.{});

    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    try testing.expect(walkable(result.words));
    try testing.expectEqual(@as(u32, 2), result.stats.hoisted_lengths);
    try testing.expectEqual(@as(u32, 2), result.stats.runtime_array_clamps);
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    // main: label, two variables, then the length.
    const main_label = find(list, op_label, 0, id_label).?;
    var main_at: usize = 0;
    for (list, 0..) |instruction, index| if (instruction.offset == main_label.offset) {
        main_at = index;
    };
    try testing.expectEqual(op_variable, list[main_at + 1].opcode);
    try testing.expectEqual(op_variable, list[main_at + 2].opcode);
    try testing.expectEqual(op_array_length, list[main_at + 3].opcode);
    const helper_label = find(list, op_label, 0, id_helper_label).?;
    var helper_at: usize = 0;
    for (list, 0..) |instruction, index| if (instruction.offset == helper_label.offset) {
        helper_at = index;
    };
    try testing.expectEqual(op_array_length, list[helper_at + 1].opcode);
    // Each function uses its own measurement.
    const main_clamp = find(list, op_ext_inst, 1, find(list, op_access_chain, 1, id_chain).?.operands[4]).?;
    const helper_clamp = find(list, op_ext_inst, 1, find(list, op_access_chain, 1, id_helper_chain).?.operands[4]).?;
    try testing.expect(main_clamp.operands[5] != helper_clamp.operands[5]);
}

test "an in-bounds access chain keeps its opcode" {
    var module = try edramModule(true, false, false);
    defer module.deinit();
    // Turn the chain into OpInBoundsAccessChain.
    var offset: usize = 5;
    while (offset < module.words.items.len) {
        const count = wordCountOf(module.words.items[offset]);
        if (opcodeOf(module.words.items[offset]) == op_access_chain) {
            module.words.items[offset] = instructionWord(op_in_bounds_access_chain, count);
        }
        offset += count;
    }
    const result = try harden(testing.allocator, module.words.items);
    defer testing.allocator.free(result.words);
    var storage: [64]Instruction = undefined;
    const list = instructions(result.words, &storage);
    try testing.expectEqual(@as(u32, 1), result.stats.runtime_array_clamps);
    try testing.expect(find(list, op_in_bounds_access_chain, 1, id_chain) != null);
    try testing.expect(find(list, op_access_chain, 1, id_chain) == null);
}

test "a module the walker cannot read is refused, not half-rewritten" {
    try testing.expectEqual(Refusal.not_spirv, (try harden(testing.allocator, &.{ 1, 2, 3, 4, 5 })).refusal);
    var module = try edramModule(true, false, false);
    defer module.deinit();
    // The last instruction claims more words than the module has.
    module.words.items[module.words.items.len - 1] = instructionWord(op_function_end, 9);
    const truncated = try harden(testing.allocator, module.words.items);
    try testing.expectEqual(Refusal.malformed, truncated.refusal);
    try testing.expect(!truncated.changed());
    var huge = try edramModule(true, false, false);
    defer huge.deinit();
    huge.words.items[3] = max_bound;
    try testing.expectEqual(Refusal.id_space, (try harden(testing.allocator, huge.words.items)).refusal);
}
