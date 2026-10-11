//! Xenos rectangle lists on a host with no geometry shader.
//!
//! ## The gap this closes
//!
//! A Xenos `kRectangleList` gives three vertices; the fourth corner is
//! derived, opposite the second: `D = v0 + v2 - v1`. Xenia expands that with
//! a geometry shader, or - when the device reports no `geometryShader`, which
//! is every Metal host - with the `kRectangleListAsTriangleStrip` vertex
//! shader fallback. `PrimitiveProcessor` prepares that fallback: a
//! two-triangle strip per rectangle, drawn from a builtin index buffer whose
//! values encode *"host vertex index within the pair in the lower 2 bits,
//! guest primitive index in the rest"*, with `0xFFFFFFFF` primitive restarts
//! between rectangles.
//!
//! The Vulkan backend never implements the shader half.
//! `spirv_shader_translator.cc` handles `kPointListAsTriangleStrip` at four
//! sites and `kRectangleListAsTriangleStrip` nowhere - the name survives only
//! in a comment. `VulkanCommandProcessor::IssueDraw` rejects the enum for
//! that reason, and Rosette's `xenia_issue_draw_patch` turns the rejection
//! into an admission. So the draw reaches the device with strip topology and
//! an *unmodified* shader that reads the encoded index as if it were a plain
//! guest vertex index. For rectangle 0 that accidentally reads guest vertices
//! 0, 1 and 2; for every rectangle after it the indices are wrong outright;
//! and the fourth corner is never synthesised at all. On Halo 3's title
//! screen the result is one correct triangle and a clean diagonal seam.
//!
//! ## What this does instead
//!
//! It rewrites the guest's vertex shader so it can perform the expansion
//! itself, and leaves the shader's behaviour for every other draw exactly as
//! it was. The switch is carried in the vertex index: Xenos indices are
//! 24-bit (`kVertexIndexMask`), so the top bit is free. Rosette tags the
//! indices of a rectangle draw; a shader that sees an untagged index runs the
//! guest body once with that index, which is what it did before.
//!
//! Doing it this way means there is no second pipeline and no draw-time
//! shader swap: one transformed module serves both kinds of draw, and the
//! cost on an ordinary vertex is one mask and one branch.
//!
//! The transform:
//!
//!   - adds a `Private` integer that stands in for the vertex index, and
//!     repoints every load of the `VertexIndex` builtin inside the shader at
//!     it, so the guest body reads whatever index this shader chooses;
//!   - makes the old entry point an ordinary function and writes a new one;
//!   - in the new entry point: untagged, store the index and call the body
//!     once; tagged, decode `i = index >> 2` and `j = index & 3`, call the
//!     body with each of `3i`, `3i + 1`, `3i + 2`, and choose the strip's
//!     orientation from the longest edge;
//!   - select an original corner for `j < 3`, or write
//!     `(second - first) + third` into every float-typed output for `j == 3`,
//!     with Xenia's NoContraction decorations. Output variables are
//!     readable in SPIR-V, so the corner is derived from the shaded values
//!     rather than from vertex data whose layout lives in fetch constants
//!     this bridge cannot see.
//!
//! Only float scalars and float vectors are combined, including float members
//! of a block such as `gl_PerVertex`. Anything else keeps the value the third
//! call left, which is the closest vertex to the derived corner. A
//! `CullDistance` output is normally refused: the transformed helper entry
//! point makes that output explicit, but MoltenVK's Metal backend does not
//! support that output. A conservative prepass can remove a trailing
//! CullDistance member only when it proves the member is unused and the block
//! has no escaping aliases. Active or uncertain cull output remains unchanged,
//! preserving guest semantics and valid MSL.
//!
//! ## What it refuses
//!
//! Every shape assumption is checked, and a module that does not match is
//! returned untouched rather than half-rewritten: a wrong guess here is a
//! device loss or a corrupted frame, and the untransformed module is exactly
//! the behaviour of every run before this one. `expand` reports which
//! assumption failed so a refusal is attributable.

const std = @import("std");

pub const magic: u32 = 0x0723_0203;

/// Set by Rosette on the indices of a rectangle draw. Xenos vertex indices
/// are 24 bits, so nothing the guest supplies can collide with it.
pub const rect_tag: u32 = 0x8000_0000;

pub const Refusal = enum {
    none,
    /// Not a SPIR-V module, or not one this host's byte order can read.
    not_spirv,
    /// The module has no `Vertex` entry point, so it is not a vertex shader.
    not_vertex,
    /// No variable carries the `VertexIndex` builtin.
    no_vertex_index,
    /// The vertex index is not an integer behind a pointer, or its type could
    /// not be resolved.
    vertex_index_shape,
    /// The entry point's function could not be located in the module.
    entry_function,
    /// The module declares more outputs than this transform tracks.
    too_many_outputs,
    /// An id would exceed what the transform can allocate.
    id_space,
    /// The shader already decodes the encoded index itself, so Xenia applied
    /// one of the `...AsTriangleStrip` modifications to it. Point lists take
    /// that path and it *is* implemented in the SPIR-V translator; expanding
    /// it a second time would break it.
    already_expanded,
    /// The output interface contains `CullDistance`, which MoltenVK's Metal
    /// backend does not expose. Calling the old entry point from the rewritten
    /// wrapper makes SPIRV-Cross emit invalid MSL for that output.
    cull_distance_output,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .none => "none",
            .not_spirv => "not-spirv",
            .not_vertex => "not-a-vertex-shader",
            .no_vertex_index => "no-vertex-index-builtin",
            .vertex_index_shape => "vertex-index-type-unresolved",
            .entry_function => "entry-function-not-found",
            .too_many_outputs => "too-many-outputs",
            .id_space => "id-space-exhausted",
            .already_expanded => "already-expanded-by-the-guest",
            .cull_distance_output => "cull-distance-output-metal-unsupported",
        };
    }
};

/// Location of the CullDistance decoration that prevented a rectangle
/// shader rewrite. `member_index` is null when BuiltIn is attached directly
/// to the output variable; otherwise `interface_type` is the output block.
pub const CullDistanceSite = struct {
    variable: u32 = 0,
    interface_type: u32 = 0,
    member_index: ?u32 = null,
};

pub const Result = struct {
    /// The rewritten module, or an empty slice when `refusal` is set. Owned
    /// by the caller.
    words: []u32 = &.{},
    refusal: Refusal = .none,
    /// Outputs whose value is derived for the fourth corner.
    combined_outputs: u32 = 0,
    /// Loads of the vertex index that were repointed at the private copy.
    repointed_loads: u32 = 0,
    /// Populated only for `.cull_distance_output`, to make the unsupported
    /// output shape visible without changing the guest module.
    cull_distance_site: ?CullDistanceSite = null,
    /// A dead trailing CullDistance interface member was removed before the
    /// rectangle transform. Set only when the transformed module was built.
    removed_unused_cull_distance: bool = false,
};

// -- SPIR-V opcodes and enumerants this transform needs ----------------------

const op_name: u16 = 5;
const op_member_name: u16 = 6;
const op_entry_point: u16 = 15;
const op_execution_mode: u16 = 16;
const op_execution_mode_id: u16 = 331;
const op_type_void: u16 = 19;
const op_type_bool: u16 = 20;
const op_type_int: u16 = 21;
const op_type_float: u16 = 22;
const op_type_vector: u16 = 23;
const op_type_array: u16 = 28;
const op_type_struct: u16 = 30;
const op_type_pointer: u16 = 32;
const op_type_function: u16 = 33;
const op_constant: u16 = 43;
const op_function: u16 = 54;
const op_function_end: u16 = 56;
const op_function_call: u16 = 57;
const op_variable: u16 = 59;
const op_load: u16 = 61;
const op_store: u16 = 62;
const op_access_chain: u16 = 65;
const op_in_bounds_access_chain: u16 = 66;
const op_group_member_decorate: u16 = 75;
const op_decorate: u16 = 71;
const op_composite_extract: u16 = 81;
const op_composite_construct: u16 = 80;
const op_i_sub: u16 = 130;
const op_f_mul: u16 = 133;
const op_select: u16 = 169;
const op_s_less_than: u16 = 177;
const op_f_ord_greater_than: u16 = 186;
const op_logical_and: u16 = 167;
const op_member_decorate: u16 = 72;
const op_i_add: u16 = 128;
const op_i_mul: u16 = 132;
const op_f_add: u16 = 129;
const op_f_sub: u16 = 131;
const op_shift_right_logical: u16 = 194;
const op_bitwise_and: u16 = 199;
const op_i_equal: u16 = 170;
const op_i_not_equal: u16 = 171;
const op_label: u16 = 248;
const op_branch: u16 = 249;
const op_branch_conditional: u16 = 250;
const op_return: u16 = 253;
const op_selection_merge: u16 = 247;

const storage_class_input: u32 = 1;
const storage_class_output: u32 = 3;
const storage_class_private: u32 = 6;
const decoration_builtin: u32 = 11;
const decoration_no_contraction: u32 = 42;
const builtin_vertex_index: u32 = 42;
const builtin_position: u32 = 0;
const builtin_cull_distance: u32 = 4;
const execution_model_vertex: u32 = 0;
const selection_control_none: u32 = 0;
const function_control_none: u32 = 0;

const max_outputs: usize = 32;
const max_struct_members: usize = 32;

fn opcodeOf(word: u32) u16 {
    return @truncate(word & 0xFFFF);
}

fn wordCountOf(word: u32) u16 {
    return @truncate(word >> 16);
}

fn instructionWord(opcode: u16, word_count: u16) u32 {
    return (@as(u32, word_count) << 16) | @as(u32, opcode);
}

/// A float scalar or a vector of floats: the only shapes whose fourth corner
/// this transform derives.
const Combinable = struct {
    /// The variable, or the block member's parent variable.
    variable: u32,
    /// Member index within a block, or null for a whole variable.
    member: ?u32,
    /// A scalar/vector element of an output array (including a block member).
    element: ?u32 = null,
    /// The value type being combined.
    value_type: u32,
};

const Module = struct {
    words: []const u32,
    id_bound: u32,

    entry_point_word: usize = 0,
    entry_function: u32 = 0,
    vertex_index_variable: u32 = 0,
    vertex_index_pointer_type: u32 = 0,
    vertex_index_value_type: u32 = 0,
    entry_function_word: usize = 0,

    type_void: u32 = 0,
    type_bool: u32 = 0,
};

const UnusedCullDistance = struct {
    variable: u32,
    structure: u32,
    member: u32,
    member_count: u32,
};

/// Remove a trailing CullDistance member only when the output is provably
/// dead: the sole output variable has one access-chain path to non-CullDistance
/// members, and no pointer escapes or whole-struct operation use it. This is
/// needed because MoltenVK's MSL backend cannot declare that output. Any
/// uncertain interface stays byte-for-byte unchanged.
fn stripUnusedCullDistanceOutput(allocator: std.mem.Allocator, words: []const u32) error{OutOfMemory}!?[]u32 {
    if (words.len < 5 or words[0] != magic) return null;

    var pointer_storage = std.AutoHashMap(u32, u32).init(allocator);
    defer pointer_storage.deinit();
    var pointer_pointee = std.AutoHashMap(u32, u32).init(allocator);
    defer pointer_pointee.deinit();
    var variable_type = std.AutoHashMap(u32, u32).init(allocator);
    defer variable_type.deinit();
    var variable_storage = std.AutoHashMap(u32, u32).init(allocator);
    defer variable_storage.deinit();
    var structure_member_counts = std.AutoHashMap(u32, u32).init(allocator);
    defer structure_member_counts.deinit();
    var constant_values = std.AutoHashMap(u32, u32).init(allocator);
    defer constant_values.deinit();
    var cull_members = std.AutoHashMap(u32, u32).init(allocator);
    defer cull_members.deinit();
    var direct_cull_variables = std.AutoHashMap(u32, void).init(allocator);
    defer direct_cull_variables.deinit();

    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (count == 0 or offset + count > words.len) return null;
        const opcode = opcodeOf(words[offset]);
        const operands = words[offset + 1 .. offset + count];
        switch (opcode) {
            op_type_pointer => if (operands.len >= 3) {
                try pointer_storage.put(operands[0], operands[1]);
                try pointer_pointee.put(operands[0], operands[2]);
            },
            op_variable => if (operands.len >= 3) {
                try variable_type.put(operands[1], operands[0]);
                try variable_storage.put(operands[1], operands[2]);
            },
            op_type_struct => if (operands.len >= 1) {
                try structure_member_counts.put(operands[0], @intCast(operands.len - 1));
            },
            op_constant => if (operands.len >= 3) {
                try constant_values.put(operands[1], operands[2]);
            },
            op_member_decorate => if (operands.len >= 4 and operands[2] == decoration_builtin and operands[3] == builtin_cull_distance) {
                if (cull_members.contains(operands[0])) return null;
                try cull_members.put(operands[0], operands[1]);
            },
            op_decorate => if (operands.len >= 3 and operands[1] == decoration_builtin and operands[2] == builtin_cull_distance) {
                try direct_cull_variables.put(operands[0], {});
            },
            else => {},
        }
        offset += count;
    }
    // A single dead interface field is the only case this pass repairs. If
    // the module has another CullDistance output, leave all of it untouched.
    if (offset != words.len or cull_members.count() != 1) return null;

    var candidate: ?UnusedCullDistance = null;
    var output_iter = variable_storage.iterator();
    while (output_iter.next()) |entry| {
        if (entry.value_ptr.* != storage_class_output) continue;
        const variable = entry.key_ptr.*;
        if (direct_cull_variables.contains(variable)) return null;
        const pointer = variable_type.get(variable) orelse continue;
        const structure = pointer_pointee.get(pointer) orelse continue;
        const member = cull_members.get(structure) orelse continue;
        const member_count = structure_member_counts.get(structure) orelse return null;
        if (member_count == 0 or member + 1 != member_count) return null;
        if (candidate != null) return null;
        candidate = .{ .variable = variable, .structure = structure, .member = member, .member_count = member_count };
    }
    const site = candidate orelse return null;

    // The block type must only have its one Output pointer type. A function,
    // input, or storage-buffer use would make deleting the final member an
    // ABI change beyond this shader's unused stage output.
    var matching_pointer_types: u32 = 0;
    var pointer_iter = pointer_pointee.iterator();
    while (pointer_iter.next()) |entry| {
        if (entry.value_ptr.* != site.structure) continue;
        matching_pointer_types += 1;
        if (pointer_storage.get(entry.key_ptr.*) != storage_class_output) return null;
    }
    if (matching_pointer_types != 1) return null;

    // No whole-struct reads/writes, pointer copies, function arguments, or
    // unknown escapes are allowed. Access chains are safe only when their
    // first literal member index is a known, non-CullDistance member.
    offset = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        const opcode = opcodeOf(words[offset]);
        const operands = words[offset + 1 .. offset + count];
        if (opcode == op_access_chain or opcode == op_in_bounds_access_chain) {
            if (operands.len >= 4 and operands[2] == site.variable) {
                const member = constant_values.get(operands[3]) orelse return null;
                if (member >= site.member_count or member == site.member) return null;
                for (operands[0..2]) |operand| if (operand == site.variable) return null;
                for (operands[4..]) |operand| if (operand == site.variable) return null;
                offset += count;
                continue;
            }
        }
        if (opcode == op_variable and operands.len >= 2 and operands[1] == site.variable) {
            offset += count;
            continue;
        }
        if (opcode == op_name and operands.len >= 1 and operands[0] == site.variable) {
            offset += count;
            continue;
        }
        if (opcode == op_decorate and operands.len >= 1 and operands[0] == site.variable) {
            offset += count;
            continue;
        }
        if (opcode == op_entry_point and operands.len >= 3) {
            var string_end: ?usize = null;
            var word_index: usize = 2;
            while (word_index < operands.len and string_end == null) : (word_index += 1) {
                const string_word = operands[word_index];
                for (0..4) |byte_index| {
                    if (@as(u8, @truncate(string_word >> @intCast(byte_index * 8))) == 0) {
                        string_end = word_index + 1;
                        break;
                    }
                }
            }
            const interface_start = string_end orelse return null;
            if (interface_start <= operands.len and
                std.mem.indexOfScalar(u32, operands[interface_start..], site.variable) != null)
            {
                offset += count;
                continue;
            }
        }
        if (opcode == op_member_name and operands.len >= 2 and operands[0] == site.structure and operands[1] == site.member) {
            offset += count;
            continue;
        }
        if (opcode == op_member_decorate and operands.len >= 2 and operands[0] == site.structure and operands[1] == site.member) {
            offset += count;
            continue;
        }
        if (opcode == op_group_member_decorate) {
            var pair: usize = 1;
            while (pair + 1 < operands.len) : (pair += 2) {
                if (operands[pair] == site.structure and operands[pair + 1] == site.member) return null;
            }
        }
        if (std.mem.indexOfScalar(u32, operands, site.variable) != null) return null;
        offset += count;
    }

    var stripped: std.ArrayList(u32) = .empty;
    errdefer stripped.deinit(allocator);
    try stripped.appendSlice(allocator, words[0..5]);
    offset = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        const opcode = opcodeOf(words[offset]);
        const operands = words[offset + 1 .. offset + count];
        if ((opcode == op_member_name or opcode == op_member_decorate) and operands.len >= 2 and
            operands[0] == site.structure and operands[1] == site.member)
        {
            offset += count;
            continue;
        }
        if (opcode == op_type_struct and operands.len == site.member_count + 1 and operands[0] == site.structure) {
            try stripped.append(allocator, instructionWord(op_type_struct, @intCast(count - 1)));
            try stripped.appendSlice(allocator, operands[0 .. operands.len - 1]);
        } else {
            try stripped.appendSlice(allocator, words[offset .. offset + count]);
        }
        offset += count;
    }
    return try stripped.toOwnedSlice(allocator);
}

pub fn expand(allocator: std.mem.Allocator, words: []const u32) error{OutOfMemory}!Result {
    if (try stripUnusedCullDistanceOutput(allocator, words)) |stripped| {
        defer allocator.free(stripped);
        var result = try expandModule(allocator, stripped);
        if (result.refusal == .none) result.removed_unused_cull_distance = true;
        return result;
    }
    return expandModule(allocator, words);
}

fn expandModule(allocator: std.mem.Allocator, words: []const u32) error{OutOfMemory}!Result {
    if (words.len < 5 or words[0] != magic) return .{ .refusal = .not_spirv };

    var module = Module{ .words = words, .id_bound = words[3] };

    // ---- pass one: learn the module's shape --------------------------------
    var builtin_vertex_index_id: u32 = 0;
    // Both `OpDecorate %variable BuiltIn CullDistance` and
    // `OpMemberDecorate %block %member BuiltIn CullDistance` are recorded in
    // this ID set. SPIR-V IDs are module-global and unique, so the later
    // output-interface check can test either form without another map.
    const CullDistanceDecoration = struct { member_index: ?u32 = null };
    var cull_distance_builtins = std.AutoHashMap(u32, CullDistanceDecoration).init(allocator);
    defer cull_distance_builtins.deinit();
    // id -> defining instruction offset, for types and variables.
    var pointer_storage = std.AutoHashMap(u32, u32).init(allocator);
    defer pointer_storage.deinit();
    var pointer_pointee = std.AutoHashMap(u32, u32).init(allocator);
    defer pointer_pointee.deinit();
    var variable_type = std.AutoHashMap(u32, u32).init(allocator);
    defer variable_type.deinit();
    var variable_storage = std.AutoHashMap(u32, u32).init(allocator);
    defer variable_storage.deinit();
    var float_types = std.AutoHashMap(u32, void).init(allocator);
    defer float_types.deinit();
    var vector_of_float = std.AutoHashMap(u32, void).init(allocator);
    defer vector_of_float.deinit();
    var vector_component = std.AutoHashMap(u32, u32).init(allocator);
    defer vector_component.deinit();
    var vector_length = std.AutoHashMap(u32, u32).init(allocator);
    defer vector_length.deinit();
    // Which output carries `gl_Position`. Xenia picks the strip's orientation
    // from the shaded positions, so without it there is no orientation to
    // pick and the canonical strip is the only option.
    var position_variable: u32 = 0;
    var position_member: ?u32 = null;
    var position_struct: u32 = 0;
    var struct_members = std.AutoHashMap(u32, []const u32).init(allocator);
    defer struct_members.deinit();
    var array_element_types = std.AutoHashMap(u32, u32).init(allocator);
    defer array_element_types.deinit();
    var array_length_ids = std.AutoHashMap(u32, u32).init(allocator);
    defer array_length_ids.deinit();
    var constant_values = std.AutoHashMap(u32, u32).init(allocator);
    defer constant_values.deinit();
    var int_types = std.AutoHashMap(u32, void).init(allocator);
    defer int_types.deinit();
    // Results of loading the vertex index, and whether any of them is shifted
    // right - the shape of a guest-side decode of the encoded index.
    var vertex_index_loads = std.AutoHashMap(u32, void).init(allocator);
    defer vertex_index_loads.deinit();
    var guest_decodes_index = false;
    // SPIR-V requires type and constant declarations to be unique: two
    // `OpTypePointer` with the same storage class and pointee *are* the same
    // type, and a second declaration is invalid. Reuse what the module has.
    var existing_pointer = std.AutoHashMap(u64, u32).init(allocator);
    defer existing_pointer.deinit();
    var existing_constant = std.AutoHashMap(u64, u32).init(allocator);
    defer existing_constant.deinit();
    var existing_void_fn: u32 = 0;
    var execution_mode_words: std.ArrayList(usize) = .empty;
    defer execution_mode_words.deinit(allocator);

    var offset: usize = 5;
    while (offset < words.len) {
        const header = words[offset];
        const count = wordCountOf(header);
        if (count == 0 or offset + count > words.len) return .{ .refusal = .not_spirv };
        const opcode = opcodeOf(header);
        const operands = words[offset + 1 .. offset + count];
        switch (opcode) {
            op_entry_point => {
                if (operands.len >= 2 and operands[0] == execution_model_vertex) {
                    module.entry_point_word = offset;
                    module.entry_function = operands[1];
                }
            },
            op_decorate => {
                if (operands.len >= 3 and operands[1] == decoration_builtin) {
                    if (operands[2] == builtin_vertex_index) builtin_vertex_index_id = operands[0];
                    if (operands[2] == builtin_position) position_variable = operands[0];
                    if (operands[2] == builtin_cull_distance) try cull_distance_builtins.put(operands[0], .{});
                }
            },
            op_member_decorate => {
                if (operands.len >= 4 and operands[2] == decoration_builtin and operands[3] == builtin_cull_distance) {
                    try cull_distance_builtins.put(operands[0], .{ .member_index = operands[1] });
                }
                if (operands.len >= 4 and operands[2] == decoration_builtin and
                    operands[3] == builtin_position)
                {
                    position_struct = operands[0];
                    position_member = operands[1];
                }
            },
            op_type_void => if (operands.len >= 1) {
                module.type_void = operands[0];
            },
            op_type_bool => if (operands.len >= 1) {
                module.type_bool = operands[0];
            },
            op_type_int => if (operands.len >= 1) {
                try int_types.put(operands[0], {});
            },
            op_type_float => if (operands.len >= 1) {
                try float_types.put(operands[0], {});
            },
            op_type_vector => if (operands.len >= 3) {
                if (float_types.contains(operands[1])) try vector_of_float.put(operands[0], {});
                try vector_component.put(operands[0], operands[1]);
                try vector_length.put(operands[0], operands[2]);
            },
            op_type_struct => if (operands.len >= 1) {
                try struct_members.put(operands[0], operands[1..]);
            },
            op_type_array => if (operands.len >= 3) {
                try array_element_types.put(operands[0], operands[1]);
                try array_length_ids.put(operands[0], operands[2]);
            },
            op_type_pointer => if (operands.len >= 3) {
                try pointer_storage.put(operands[0], operands[1]);
                try pointer_pointee.put(operands[0], operands[2]);
                try existing_pointer.put((@as(u64, operands[1]) << 32) | operands[2], operands[0]);
            },
            op_constant => if (operands.len >= 3) {
                try existing_constant.put((@as(u64, operands[0]) << 32) | operands[2], operands[1]);
                try constant_values.put(operands[1], operands[2]);
            },
            op_type_function => if (operands.len == 2) {
                if (operands[1] == module.type_void) existing_void_fn = operands[0];
            },
            op_execution_mode, op_execution_mode_id => if (operands.len >= 1) {
                if (operands[0] == module.entry_function) try execution_mode_words.append(allocator, offset);
            },
            op_variable => if (operands.len >= 3) {
                try variable_type.put(operands[1], operands[0]);
                try variable_storage.put(operands[1], operands[2]);
            },
            op_function => if (operands.len >= 2 and operands[1] == module.entry_function) {
                module.entry_function_word = offset;
            },
            op_load => if (operands.len >= 3 and operands[2] == builtin_vertex_index_id and builtin_vertex_index_id != 0) {
                try vertex_index_loads.put(operands[1], {});
            },
            op_shift_right_logical => if (operands.len >= 3) {
                if (vertex_index_loads.contains(operands[2])) guest_decodes_index = true;
            },
            else => {},
        }
        offset += count;
    }

    if (module.entry_point_word == 0 or module.entry_function == 0) return .{ .refusal = .not_vertex };
    if (builtin_vertex_index_id == 0) return .{ .refusal = .no_vertex_index };
    if (module.entry_function_word == 0) return .{ .refusal = .entry_function };
    if (guest_decodes_index) return .{ .refusal = .already_expanded };

    module.vertex_index_variable = builtin_vertex_index_id;
    module.vertex_index_pointer_type = variable_type.get(builtin_vertex_index_id) orelse
        return .{ .refusal = .vertex_index_shape };
    module.vertex_index_value_type = pointer_pointee.get(module.vertex_index_pointer_type) orelse
        return .{ .refusal = .vertex_index_shape };
    if (!int_types.contains(module.vertex_index_value_type)) return .{ .refusal = .vertex_index_shape };
    if (module.type_void == 0) return .{ .refusal = .vertex_index_shape };

    // The wrapper calls the original entry point as a helper so it can shade
    // the three source vertices and combine their outputs. In the current
    // SPIR-V-to-MSL route, the helper's explicit output structure cannot
    // represent this CullDistance interface shape. Keep the module
    // byte-for-byte untouched and report the exact decorated location.
    var output_variables = variable_storage.iterator();
    while (output_variables.next()) |entry| {
        if (entry.value_ptr.* != storage_class_output) continue;
        const variable = entry.key_ptr.*;
        const pointer = variable_type.get(variable) orelse continue;
        const pointee = pointer_pointee.get(pointer) orelse continue;
        if (cull_distance_builtins.get(variable)) |decoration| return .{
            .refusal = .cull_distance_output,
            .cull_distance_site = .{ .variable = variable, .interface_type = pointee, .member_index = decoration.member_index },
        };
        if (cull_distance_builtins.get(pointee)) |decoration| return .{
            .refusal = .cull_distance_output,
            .cull_distance_site = .{ .variable = variable, .interface_type = pointee, .member_index = decoration.member_index },
        };
    }

    // ---- the outputs whose fourth corner is derived -------------------------
    var combinable: [max_outputs]Combinable = undefined;
    var combinable_count: usize = 0;
    var output_iter = variable_storage.iterator();
    while (output_iter.next()) |entry| {
        if (entry.value_ptr.* != storage_class_output) continue;
        const variable = entry.key_ptr.*;
        const pointer = variable_type.get(variable) orelse continue;
        const pointee = pointer_pointee.get(pointer) orelse continue;
        const members = struct_members.get(pointee) orelse &[_]u32{pointee};
        for (members, 0..) |member_type, index| {
            const member: ?u32 = if (struct_members.contains(pointee)) @intCast(index) else null;
            if (float_types.contains(member_type) or vector_of_float.contains(member_type)) {
                if (combinable_count == max_outputs) return .{ .refusal = .too_many_outputs };
                combinable[combinable_count] = .{ .variable = variable, .member = member, .value_type = member_type };
                combinable_count += 1;
                continue;
            }
            // gl_PerVertex's ClipDistance and CullDistance are float arrays.
            // Every emitted corner needs its own distance for every plane;
            // keeping the third guest vertex's distances clips a different
            // shape than the generated position and tears the rectangle.
            const element_type = array_element_types.get(member_type) orelse continue;
            if (!float_types.contains(element_type) and !vector_of_float.contains(element_type)) continue;
            const length_id = array_length_ids.get(member_type) orelse continue;
            const length = constant_values.get(length_id) orelse continue;
            if (length > max_outputs - combinable_count) return .{ .refusal = .too_many_outputs };
            for (0..length) |element| {
                combinable[combinable_count] = .{
                    .variable = variable,
                    .member = member,
                    .element = @intCast(element),
                    .value_type = element_type,
                };
                combinable_count += 1;
            }
        }
    }

    // Which entry in that list is `gl_Position`, either as a variable the
    // module decorated directly or as the member of a `gl_PerVertex` block.
    var position_slot: ?usize = null;
    for (0..combinable_count) |index| {
        const entry = combinable[index];
        if (entry.member) |member| {
            if (entry.element != null) continue;
            const pointer = variable_type.get(entry.variable) orelse continue;
            const pointee = pointer_pointee.get(pointer) orelse continue;
            if (position_struct != 0 and pointee == position_struct and position_member == member) {
                position_slot = index;
                break;
            }
        } else if (position_variable != 0 and entry.variable == position_variable) {
            position_slot = index;
            break;
        }
    }

    // ---- id allocation ------------------------------------------------------
    var next_id = module.id_bound;
    const Allocator2 = struct {
        next: *u32,
        fn take(self: @This()) u32 {
            const id = self.next.*;
            self.next.* += 1;
            return id;
        }
    };
    const ids = Allocator2{ .next = &next_id };

    const int_type = module.vertex_index_value_type;
    const private_key = (@as(u64, storage_class_private) << 32) | int_type;
    const existing_private_pointer = existing_pointer.get(private_key) orelse 0;
    const private_pointer_type = if (existing_private_pointer != 0) existing_private_pointer else ids.take();
    const need_private_pointer_type = existing_private_pointer == 0;
    const private_index = ids.take();
    const bool_type = if (module.type_bool != 0) module.type_bool else ids.take();
    const need_bool_type = module.type_bool == 0;
    var bool_vector_type: [5]u32 = @splat(0);
    var bool_vector_new: [5]bool = @splat(false);
    var vector_iter = vector_component.iterator();
    while (vector_iter.next()) |entry| {
        if (entry.value_ptr.* != bool_type) continue;
        const length = vector_length.get(entry.key_ptr.*) orelse continue;
        if (length >= 2 and length <= 4) bool_vector_type[length] = entry.key_ptr.*;
    }
    for (combinable[0..combinable_count]) |entry| {
        const length = vector_length.get(entry.value_type) orelse continue;
        if (length < 2 or length > 4) return .{ .refusal = .vertex_index_shape };
        if (bool_vector_type[length] == 0) {
            bool_vector_type[length] = ids.take();
            bool_vector_new[length] = true;
        }
    }
    const fn_void_type = if (existing_void_fn != 0) existing_void_fn else ids.take();
    const need_fn_void_type = existing_void_fn == 0;
    const new_main = ids.take();

    const wanted_constants = [_]u32{ 0, 1, 2, 3, rect_tag, ~rect_tag };
    var constant_ids: [wanted_constants.len]u32 = undefined;
    var constant_is_new: [wanted_constants.len]bool = undefined;
    for (wanted_constants, 0..) |value, index| {
        const key = (@as(u64, int_type) << 32) | value;
        if (existing_constant.get(key)) |found| {
            constant_ids[index] = found;
            constant_is_new[index] = false;
        } else {
            constant_ids[index] = ids.take();
            constant_is_new[index] = true;
            try existing_constant.put(key, constant_ids[index]);
        }
    }
    const const_zero = constant_ids[0];
    const const_one = constant_ids[1];
    const const_two = constant_ids[2];
    const const_three = constant_ids[3];
    const const_tag = constant_ids[4];
    const const_untag = constant_ids[5];

    // Pointer types for reading block members back out of an output.
    var member_pointer_type: [max_outputs]u32 = undefined;
    var member_pointer_is_new: [max_outputs]bool = undefined;
    var member_constant: [max_outputs]u32 = undefined;
    var member_constant_is_new: [max_outputs]bool = undefined;
    var element_constant: [max_outputs]u32 = undefined;
    var element_constant_is_new: [max_outputs]bool = undefined;
    for (0..combinable_count) |index| {
        member_pointer_is_new[index] = false;
        member_constant_is_new[index] = false;
        element_constant_is_new[index] = false;
        member_pointer_type[index] = 0;
        member_constant[index] = 0;
        element_constant[index] = 0;
        const member = combinable[index].member;
        const element = combinable[index].element;
        if (member == null and element == null) continue;
        const pointer_key = (@as(u64, storage_class_output) << 32) | combinable[index].value_type;
        if (existing_pointer.get(pointer_key)) |found| {
            member_pointer_type[index] = found;
        } else {
            member_pointer_type[index] = ids.take();
            member_pointer_is_new[index] = true;
            try existing_pointer.put(pointer_key, member_pointer_type[index]);
        }
        if (member) |member_index| {
            const constant_key = (@as(u64, int_type) << 32) | member_index;
            if (existing_constant.get(constant_key)) |found| {
                member_constant[index] = found;
            } else {
                member_constant[index] = ids.take();
                member_constant_is_new[index] = true;
                try existing_constant.put(constant_key, member_constant[index]);
            }
        }
        if (element) |element_index| {
            const constant_key = (@as(u64, int_type) << 32) | element_index;
            if (existing_constant.get(constant_key)) |found| {
                element_constant[index] = found;
            } else {
                element_constant[index] = ids.take();
                element_constant_is_new[index] = true;
                try existing_constant.put(constant_key, element_constant[index]);
            }
        }
    }

    // ---- build -------------------------------------------------------------
    var out: std.ArrayList(u32) = .empty;
    defer out.deinit(allocator);
    var precise_decorations: std.ArrayList(u32) = .empty;
    defer precise_decorations.deinit(allocator);

    try out.appendSlice(allocator, words[0..5]);

    var repointed: u32 = 0;
    offset = 5;
    var declarations_emitted = false;
    while (offset < words.len) {
        const header = words[offset];
        const count = wordCountOf(header);
        const opcode = opcodeOf(header);
        const instruction = words[offset .. offset + count];
        var execution_mode_target = false;
        for (execution_mode_words.items) |mode_offset| {
            if (mode_offset == offset) execution_mode_target = true;
        }

        // The new declarations go in front of the first function, which is
        // where SPIR-V requires types, constants and module-scope variables to
        // have been declared by.
        if (!declarations_emitted and opcode == op_function) {
            declarations_emitted = true;
            if (need_bool_type) {
                try out.appendSlice(allocator, &.{ instructionWord(op_type_bool, 2), bool_type });
            }
            for (2..5) |length| {
                if (bool_vector_new[length]) try out.appendSlice(allocator, &.{
                    instructionWord(op_type_vector, 4), bool_vector_type[length], bool_type, @intCast(length),
                });
            }
            if (need_private_pointer_type) try out.appendSlice(allocator, &.{
                instructionWord(op_type_pointer, 4), private_pointer_type, storage_class_private, int_type,
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_variable, 4), private_pointer_type, private_index, storage_class_private,
            });
            if (need_fn_void_type) try out.appendSlice(allocator, &.{
                instructionWord(op_type_function, 3), fn_void_type, module.type_void,
            });
            for (wanted_constants, 0..) |value, index| {
                if (!constant_is_new[index]) continue;
                try out.appendSlice(allocator, &.{
                    instructionWord(op_constant, 4), int_type, constant_ids[index], value,
                });
            }
            for (0..combinable_count) |index| {
                if (member_pointer_is_new[index]) try out.appendSlice(allocator, &.{
                    instructionWord(op_type_pointer, 4),
                    member_pointer_type[index],
                    storage_class_output,
                    combinable[index].value_type,
                });
                if (member_constant_is_new[index]) try out.appendSlice(allocator, &.{
                    instructionWord(op_constant, 4), int_type, member_constant[index], combinable[index].member.?,
                });
                if (element_constant_is_new[index]) try out.appendSlice(allocator, &.{
                    instructionWord(op_constant, 4), int_type, element_constant[index], combinable[index].element.?,
                });
            }
        }

        if (offset == module.entry_point_word) {
            // Retarget the entry point at the new function. From SPIR-V 1.4
            // the interface must list *every* global the entry point uses,
            // not only the inputs and outputs, so the private stand-in joins
            // it there and not before.
            const lists_all_globals = words[1] >= 0x0001_0400;
            const added: u16 = if (lists_all_globals) 1 else 0;
            try out.append(allocator, instructionWord(op_entry_point, count + added));
            try out.append(allocator, instruction[1]);
            try out.append(allocator, new_main);
            try out.appendSlice(allocator, instruction[3..]);
            if (lists_all_globals) try out.append(allocator, private_index);
        } else if (execution_mode_target and (opcode == op_execution_mode or opcode == op_execution_mode_id)) {
            // An execution mode names its entry point, and the entry point is
            // now a different function.
            try out.append(allocator, header);
            try out.append(allocator, new_main);
            try out.appendSlice(allocator, instruction[2..]);
        } else if (opcode == op_load and count >= 4 and instruction[3] == module.vertex_index_variable) {
            // Every read of the vertex index inside the guest body now comes
            // from whichever index this shader chose for the invocation.
            try out.appendSlice(allocator, instruction[0..3]);
            try out.append(allocator, private_index);
            try out.appendSlice(allocator, instruction[4..]);
            repointed += 1;
        } else if (opcode == op_name and count >= 3 and instruction[1] == module.entry_function) {
            // The old entry point keeps its body and loses its name, so two
            // functions are not both called "main". An OpNop here is invalid:
            // a Nop may occur only in a function block, not among decorations.
        } else {
            try out.appendSlice(allocator, instruction);
        }
        offset += count;
    }

    // ---- the new entry point ------------------------------------------------
    const label_entry = ids.take();
    const label_plain = ids.take();
    const label_rect = ids.take();
    const label_inner_merge = ids.take();
    const label_merge = ids.take();

    try out.appendSlice(allocator, &.{
        instructionWord(op_function, 5), module.type_void, new_main, function_control_none, fn_void_type,
    });
    try out.appendSlice(allocator, &.{ instructionWord(op_label, 2), label_entry });

    const raw = ids.take();
    const tagged = ids.take();
    const is_rect = ids.take();
    try out.appendSlice(allocator, &.{ instructionWord(op_load, 4), int_type, raw, module.vertex_index_variable });
    try out.appendSlice(allocator, &.{ instructionWord(op_bitwise_and, 5), int_type, tagged, raw, const_tag });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_not_equal, 5), bool_type, is_rect, tagged, const_zero });
    try out.appendSlice(allocator, &.{ instructionWord(op_selection_merge, 3), label_merge, selection_control_none });
    try out.appendSlice(allocator, &.{ instructionWord(op_branch_conditional, 4), is_rect, label_rect, label_plain });

    // Untagged: exactly what the shader did before this transform existed.
    try out.appendSlice(allocator, &.{ instructionWord(op_label, 2), label_plain });
    try out.appendSlice(allocator, &.{ instructionWord(op_store, 3), private_index, raw });
    try out.appendSlice(allocator, &.{
        instructionWord(op_function_call, 4), module.type_void, ids.take(), module.entry_function,
    });
    try out.appendSlice(allocator, &.{ instructionWord(op_branch, 2), label_merge });

    // Tagged: shade all three guest vertices, choose the strip's
    // orientation from their positions exactly as Xenia's rectangle geometry
    // shader does, and select or derive this corner from the three results.
    //
    // Xenia mirrors a vertex across the *longest* edge and rotates the strip
    // so that edge becomes the shared diagonal:
    //
    //   e0 = |v1 - v2|^2, e1 = |v2 - v0|^2, e2 = |v0 - v1|^2
    //   first = (e0 > e1 && e0 > e2) ? 0 : (e1 > e2 ? 1 : 2)
    //   strip  = first, (first + 1) % 3, (first + 2) % 3, derived
    //   derived = (v[first+1] - v[first]) + v[first+2]
    //
    // Xenia's own comment in `vulkan_pipeline_cache.cc` states it for the
    // common case: edge 1-2 longest, "v3 = -v0 + v1 + v2". The first version
    // of this transform omitted the subtraction of `v[first]`, which put
    // every derived corner exactly `v[first]` away from the rectangle: one
    // triangle of each rectangle right and the other cut along its diagonal -
    // the split across Halo 3's title screen. `fourthCorner` below is the same
    // evaluation order in plain Zig, so the formula is tested numerically rather
    // than only by the shape of the SPIR-V that implements it.
    //
    // Taking the canonical strip instead would shear every rectangle whose
    // longest edge is not 1-2.
    const untagged = ids.take();
    const rect_index = ids.take();
    const corner = ids.take();
    const base = ids.take();
    try out.appendSlice(allocator, &.{ instructionWord(op_label, 2), label_rect });
    try out.appendSlice(allocator, &.{ instructionWord(op_bitwise_and, 5), int_type, untagged, raw, const_untag });
    try out.appendSlice(allocator, &.{
        instructionWord(op_shift_right_logical, 5), int_type, rect_index, untagged, const_two,
    });
    try out.appendSlice(allocator, &.{ instructionWord(op_bitwise_and, 5), int_type, corner, untagged, const_three });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_mul, 5), int_type, base, rect_index, const_three });

    var shaded: [3][max_outputs]u32 = undefined;
    for (0..3) |vertex| {
        const index_value = if (vertex == 0) base else ids.take();
        if (vertex != 0) {
            const addend = if (vertex == 1) const_one else const_two;
            try out.appendSlice(allocator, &.{ instructionWord(op_i_add, 5), int_type, index_value, base, addend });
        }
        try out.appendSlice(allocator, &.{ instructionWord(op_store, 3), private_index, index_value });
        try out.appendSlice(allocator, &.{
            instructionWord(op_function_call, 4), module.type_void, ids.take(), module.entry_function,
        });
        for (0..combinable_count) |index| {
            shaded[vertex][index] = try emitOutputLoad(
                allocator,
                &out,
                ids.take(),
                combinable[index],
                member_pointer_type[index],
                member_constant[index],
                element_constant[index],
                &ids,
            );
        }
    }

    // The orientation. Without a position output there is nothing to measure,
    // so the canonical strip stands.
    var first: u32 = const_zero;
    if (position_slot) |slot| {
        const float_type = vector_component.get(combinable[slot].value_type) orelse 0;
        if (float_type != 0) {
            var squared: [3]u32 = undefined;
            for (0..3) |edge| {
                const a = shaded[(1 + edge) % 3][slot];
                const b = shaded[(2 + edge) % 3][slot];
                var terms: [2]u32 = undefined;
                for (0..2) |axis| {
                    const a_component = ids.take();
                    const b_component = ids.take();
                    const difference = ids.take();
                    const product = ids.take();
                    try out.appendSlice(allocator, &.{
                        instructionWord(op_composite_extract, 5), float_type, a_component, a, @intCast(axis),
                    });
                    try out.appendSlice(allocator, &.{
                        instructionWord(op_composite_extract, 5), float_type, b_component, b, @intCast(axis),
                    });
                    try out.appendSlice(allocator, &.{
                        instructionWord(op_f_sub, 5), float_type, difference, b_component, a_component,
                    });
                    try out.appendSlice(allocator, &.{
                        instructionWord(op_f_mul, 5), float_type, product, difference, difference,
                    });
                    terms[axis] = product;
                }
                squared[edge] = ids.take();
                try out.appendSlice(allocator, &.{
                    instructionWord(op_f_add, 5), float_type, squared[edge], terms[0], terms[1],
                });
            }
            const longer_than_1 = ids.take();
            const longer_than_2 = ids.take();
            const zero_is_longest = ids.take();
            const one_over_two = ids.take();
            const one_or_two = ids.take();
            const chosen = ids.take();
            try out.appendSlice(allocator, &.{
                instructionWord(op_f_ord_greater_than, 5), bool_type, longer_than_1, squared[0], squared[1],
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_f_ord_greater_than, 5), bool_type, longer_than_2, squared[0], squared[2],
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_logical_and, 5), bool_type, zero_is_longest, longer_than_1, longer_than_2,
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_f_ord_greater_than, 5), bool_type, one_over_two, squared[1], squared[2],
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_select, 6), int_type, one_or_two, one_over_two, const_one, const_two,
            });
            try out.appendSlice(allocator, &.{
                instructionWord(op_select, 6), int_type, chosen, zero_is_longest, const_zero, one_or_two,
            });
            first = chosen;
        }
    }

    // pick = (first + corner) % 3, valid for the derived corner too.
    const unwrapped = ids.take();
    const wrapped = ids.take();
    const in_range = ids.take();
    const pick = ids.take();
    const is_derived = ids.take();
    try out.appendSlice(allocator, &.{ instructionWord(op_i_add, 5), int_type, unwrapped, first, corner });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_sub, 5), int_type, wrapped, unwrapped, const_three });
    try out.appendSlice(allocator, &.{
        instructionWord(op_s_less_than, 5), bool_type, in_range, unwrapped, const_three,
    });
    try out.appendSlice(allocator, &.{
        instructionWord(op_select, 6), int_type, pick, in_range, unwrapped, wrapped,
    });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_equal, 5), bool_type, is_derived, corner, const_three });

    const first_is_0 = ids.take();
    const first_is_1 = ids.take();
    const pick_is_0 = ids.take();
    const pick_is_1 = ids.take();
    try out.appendSlice(allocator, &.{ instructionWord(op_i_equal, 5), bool_type, first_is_0, first, const_zero });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_equal, 5), bool_type, first_is_1, first, const_one });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_equal, 5), bool_type, pick_is_0, pick, const_zero });
    try out.appendSlice(allocator, &.{ instructionWord(op_i_equal, 5), bool_type, pick_is_1, pick, const_one });

    const scalar_conditions = [_]u32{ first_is_1, first_is_0, pick_is_1, pick_is_0, is_derived };
    var vector_conditions: [5][5]u32 = @splat(@splat(0));
    for (2..5) |length| {
        if (bool_vector_type[length] == 0) continue;
        for (scalar_conditions, 0..) |condition, condition_index| {
            const vector_condition = ids.take();
            vector_conditions[condition_index][length] = vector_condition;
            try out.append(allocator, instructionWord(op_composite_construct, @intCast(3 + length)));
            try out.appendSlice(allocator, &.{ bool_vector_type[length], vector_condition });
            for (0..length) |_| try out.append(allocator, condition);
        }
    }

    for (0..combinable_count) |index| {
        const value_type = combinable[index].value_type;
        const length = vector_length.get(value_type) orelse 0;
        const select_conditions = if (length == 0) scalar_conditions else [5]u32{
            vector_conditions[0][length], vector_conditions[1][length], vector_conditions[2][length],
            vector_conditions[3][length], vector_conditions[4][length],
        };
        const tail_first = ids.take();
        const at_first = ids.take();
        const tail_pick = ids.take();
        const at_pick = ids.take();
        const tail_second = ids.take();
        const at_second = ids.take();
        const tail_third = ids.take();
        const at_third = ids.take();
        const difference = ids.take();
        const derived = ids.take();
        const selected = ids.take();
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, tail_first, select_conditions[0], shaded[1][index], shaded[2][index],
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, at_first, select_conditions[1], shaded[0][index], tail_first,
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, tail_pick, select_conditions[2], shaded[1][index], shaded[2][index],
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, at_pick, select_conditions[3], shaded[0][index], tail_pick,
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, tail_second, select_conditions[0], shaded[2][index], shaded[0][index],
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, at_second, select_conditions[1], shaded[1][index], tail_second,
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, tail_third, select_conditions[0], shaded[0][index], shaded[1][index],
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, at_third, select_conditions[1], shaded[2][index], tail_third,
        });
        // Match Xenia's geometry shader's floating-point evaluation exactly:
        // (second - first) + third, with both operations NoContraction.
        // Summing all three then subtracting first twice loses low bits of
        // positions, UVs and lighting interpolants through cancellation.
        try out.appendSlice(allocator, &.{
            instructionWord(op_f_sub, 5), value_type, difference, at_second, at_first,
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_f_add, 5), value_type, derived, difference, at_third,
        });
        for ([_]u32{ difference, derived }) |precise_id| try precise_decorations.appendSlice(allocator, &.{
            instructionWord(op_decorate, 3), precise_id, decoration_no_contraction,
        });
        try out.appendSlice(allocator, &.{
            instructionWord(op_select, 6), value_type, selected, select_conditions[4], derived, at_pick,
        });
        try emitOutputStore(
            allocator,
            &out,
            combinable[index],
            member_pointer_type[index],
            member_constant[index],
            element_constant[index],
            selected,
            &ids,
        );
    }
    try out.appendSlice(allocator, &.{ instructionWord(op_branch, 2), label_inner_merge });

    try out.appendSlice(allocator, &.{ instructionWord(op_label, 2), label_inner_merge });
    try out.appendSlice(allocator, &.{ instructionWord(op_branch, 2), label_merge });
    try out.appendSlice(allocator, &.{ instructionWord(op_label, 2), label_merge });
    try out.appendSlice(allocator, &.{instructionWord(op_return, 1)});
    try out.appendSlice(allocator, &.{instructionWord(op_function_end, 1)});

    // Decorations belong before the type/constant/function declarations,
    // including when their targets are results in the new wrapper.
    var annotation_end: usize = 5;
    while (annotation_end < out.items.len) {
        const op = opcodeOf(out.items[annotation_end]);
        if (op >= op_type_void and op <= 39) break;
        annotation_end += wordCountOf(out.items[annotation_end]);
    }
    try out.insertSlice(allocator, annotation_end, precise_decorations.items);

    const produced = try out.toOwnedSlice(allocator);
    produced[3] = next_id;
    return .{
        .words = produced,
        .combined_outputs = @intCast(combinable_count),
        .repointed_loads = repointed,
    };
}

/// Read one output back, through an access chain when it is a block member.
fn emitOutputLoad(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u32),
    result: u32,
    target: Combinable,
    member_pointer: u32,
    member_index: u32,
    element_index: u32,
    ids: anytype,
) error{OutOfMemory}!u32 {
    if (target.member == null and target.element == null) {
        try out.appendSlice(allocator, &.{ instructionWord(op_load, 4), target.value_type, result, target.variable });
        return result;
    }
    const chain = ids.take();
    const index_count: u16 = @as(u16, @intFromBool(target.member != null)) + @as(u16, @intFromBool(target.element != null));
    try out.appendSlice(allocator, &.{ instructionWord(op_access_chain, 4 + index_count), member_pointer, chain, target.variable });
    if (target.member != null) try out.append(allocator, member_index);
    if (target.element != null) try out.append(allocator, element_index);
    try out.appendSlice(allocator, &.{ instructionWord(op_load, 4), target.value_type, result, chain });
    return result;
}

fn emitOutputStore(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u32),
    target: Combinable,
    member_pointer: u32,
    member_index: u32,
    element_index: u32,
    value: u32,
    ids: anytype,
) error{OutOfMemory}!void {
    if (target.member == null and target.element == null) {
        try out.appendSlice(allocator, &.{ instructionWord(op_store, 3), target.variable, value });
        return;
    }
    const chain = ids.take();
    const index_count: u16 = @as(u16, @intFromBool(target.member != null)) + @as(u16, @intFromBool(target.element != null));
    try out.appendSlice(allocator, &.{ instructionWord(op_access_chain, 4 + index_count), member_pointer, chain, target.variable });
    if (target.member != null) try out.append(allocator, member_index);
    if (target.element != null) try out.append(allocator, element_index);
    try out.appendSlice(allocator, &.{ instructionWord(op_store, 3), chain, value });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

/// A vertex shader shaped like the ones Xenia's SPIR-V translator emits: a
/// `VertexIndex` builtin that the body reads, a `gl_PerVertex`-style block
/// output and a plain vector output.
const SyntheticShader = struct {
    words: std.ArrayList(u32) = .empty,

    const id_void = 1;
    const id_int = 2;
    const id_float = 3;
    const id_vec4 = 4;
    const id_ptr_input_int = 5;
    const id_ptr_output_vec4 = 6;
    const id_fn_void = 7;
    const id_vertex_index = 8;
    const id_interpolator = 9;
    const id_main = 10;
    const id_label = 11;
    const id_loaded = 12;
    const id_block = 13;
    const id_ptr_output_block = 14;
    const id_position_var = 15;
    const id_bound = 24;

    fn emit(self: *SyntheticShader, allocator: std.mem.Allocator, opcode: u16, operands: []const u32) !void {
        try self.words.append(allocator, instructionWord(opcode, @intCast(operands.len + 1)));
        try self.words.appendSlice(allocator, operands);
    }

    const Options = struct {
        vertex: bool = true,
        with_builtin: bool = true,
        /// SPIR-V 1.4 and later list every global in the entry interface.
        version_1_4: bool = false,
        /// Declare the pointer type and integer constants the transform also
        /// wants, so the reuse path is the one under test.
        predeclare: bool = false,
        /// An execution mode naming the entry point, which has to follow it.
        execution_mode: bool = false,
        /// Decorate the block member as `gl_Position`.
        position_builtin: bool = true,
        clip_distances: bool = false,
        cull_distances: bool = false,
        cull_distance_use: bool = false,
    };

    const id_ptr_private_int = 17;
    const id_const_two = 18;
    const id_array_float = 19;
    const id_uint = 20;
    const id_clip_count = 21;
    const id_ptr_output_float = 22;
    const id_cull_member_index = 23;
    const id_cull_element_index = 24;
    const id_cull_access = 25;
    const id_float_zero = 26;

    fn build(allocator: std.mem.Allocator, options: Options) !std.ArrayList(u32) {
        const vertex = options.vertex;
        const with_builtin = options.with_builtin;
        var self = SyntheticShader{};
        try self.words.appendSlice(allocator, &.{
            magic,
            if (options.version_1_4) 0x0001_0400 else 0x0001_0300,
            0,
            id_bound + 3,
            0,
        });
        try self.emit(allocator, op_entry_point, &.{
            if (vertex) execution_model_vertex else 4,
            id_main,
            0x0000_6E69, // "in\0\0", a name word; contents do not matter here
            id_vertex_index,
            id_interpolator,
            id_position_var,
        });
        if (options.execution_mode) try self.emit(allocator, op_execution_mode, &.{ id_main, 0 });
        if (options.position_builtin) {
            try self.emit(allocator, op_member_decorate, &.{ id_block, 0, decoration_builtin, builtin_position });
        }
        try self.emit(allocator, op_name, &.{ id_main, 0x0000_6E69 });
        if (with_builtin) {
            try self.emit(allocator, op_decorate, &.{ id_vertex_index, decoration_builtin, builtin_vertex_index });
        }
        try self.emit(allocator, op_type_void, &.{id_void});
        try self.emit(allocator, op_type_int, &.{ id_int, 32, 1 });
        if (options.clip_distances or options.cull_distances) {
            try self.emit(allocator, op_type_int, &.{ id_uint, 32, 0 });
            try self.emit(allocator, op_constant, &.{ id_uint, id_clip_count, 2 });
        }
        try self.emit(allocator, op_type_float, &.{ id_float, 32 });
        try self.emit(allocator, op_type_vector, &.{ id_vec4, id_float, 4 });
        if (options.clip_distances or options.cull_distances) {
            try self.emit(allocator, op_type_array, &.{ id_array_float, id_float, id_clip_count });
            try self.emit(allocator, op_type_struct, &.{ id_block, id_vec4, id_array_float });
        } else {
            try self.emit(allocator, op_type_struct, &.{ id_block, id_vec4 });
        }
        if (options.cull_distances) {
            try self.emit(allocator, op_member_decorate, &.{ id_block, 1, decoration_builtin, builtin_cull_distance });
        }
        try self.emit(allocator, op_type_pointer, &.{ id_ptr_input_int, storage_class_input, id_int });
        try self.emit(allocator, op_type_pointer, &.{ id_ptr_output_vec4, storage_class_output, id_vec4 });
        try self.emit(allocator, op_type_pointer, &.{ id_ptr_output_block, storage_class_output, id_block });
        if (options.cull_distance_use) {
            try self.emit(allocator, op_type_pointer, &.{ id_ptr_output_float, storage_class_output, id_float });
        }
        if (options.predeclare) {
            try self.emit(allocator, op_type_pointer, &.{ id_ptr_private_int, storage_class_private, id_int });
        }
        try self.emit(allocator, op_type_function, &.{ id_fn_void, id_void });
        if (options.predeclare) {
            try self.emit(allocator, op_constant, &.{ id_int, id_const_two, 2 });
        }
        if (options.cull_distance_use) {
            try self.emit(allocator, op_constant, &.{ id_uint, id_cull_member_index, 1 });
            try self.emit(allocator, op_constant, &.{ id_uint, id_cull_element_index, 0 });
            try self.emit(allocator, op_constant, &.{ id_float, id_float_zero, 0 });
        }
        try self.emit(allocator, op_variable, &.{ id_ptr_input_int, id_vertex_index, storage_class_input });
        try self.emit(allocator, op_variable, &.{ id_ptr_output_vec4, id_interpolator, storage_class_output });
        try self.emit(allocator, op_variable, &.{ id_ptr_output_block, id_position_var, storage_class_output });
        try self.emit(allocator, op_function, &.{ id_void, id_main, function_control_none, id_fn_void });
        try self.emit(allocator, op_label, &.{id_label});
        try self.emit(allocator, op_load, &.{ id_int, id_loaded, id_vertex_index });
        if (options.cull_distance_use) {
            try self.emit(allocator, op_access_chain, &.{ id_ptr_output_float, id_cull_access, id_position_var, id_cull_member_index, id_cull_element_index });
            try self.emit(allocator, op_store, &.{ id_cull_access, id_float_zero });
        }
        try self.emit(allocator, op_return, &.{});
        try self.emit(allocator, op_function_end, &.{});
        return self.words;
    }
};

/// Every instruction has a non-zero word count and the stream ends exactly on
/// an instruction boundary. A module that fails this is one the driver would
/// reject before it reported anything useful.
fn walkable(words: []const u32) bool {
    if (words.len < 5 or words[0] != magic) return false;
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (count == 0) return false;
        if (offset + count > words.len) return false;
        offset += count;
    }
    return offset == words.len;
}

fn findEntryPointTarget(words: []const u32) ?u32 {
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (opcodeOf(words[offset]) == op_entry_point) return words[offset + 2];
        offset += count;
    }
    return null;
}

fn countOpcode(words: []const u32, opcode: u16) u32 {
    var found: u32 = 0;
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (opcodeOf(words[offset]) == opcode) found += 1;
        offset += count;
    }
    return found;
}

fn countCullDistanceDecorations(words: []const u32) u32 {
    var found: u32 = 0;
    var offset: usize = 5;
    while (offset < words.len) {
        const header = words[offset];
        const opcode = opcodeOf(header);
        const count = wordCountOf(header);
        if (opcode == op_member_decorate and count >= 5 and
            words[offset + 3] == decoration_builtin and words[offset + 4] == builtin_cull_distance)
        {
            found += 1;
        }
        if (opcode == op_decorate and count >= 4 and
            words[offset + 2] == decoration_builtin and words[offset + 3] == builtin_cull_distance)
        {
            found += 1;
        }
        offset += count;
    }
    return found;
}

test "a vertex shader gains a rectangle-expanding entry point and keeps its body" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);

    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(walkable(result.words));

    // The entry point now names a function the module did not have before,
    // and the guest body survives as an ordinary function.
    const target = findEntryPointTarget(result.words).?;
    try testing.expect(target != SyntheticShader.id_main);
    try testing.expect(target >= SyntheticShader.id_bound);
    try testing.expectEqual(@as(u32, 2), countOpcode(result.words, op_function));
    try testing.expectEqual(@as(u32, 2), countOpcode(result.words, op_function_end));

    // The body's read of the vertex index was repointed at the private copy.
    try testing.expectEqual(@as(u32, 1), result.repointed_loads);
    // Both the plain vector output and the block's float member are derived.
    try testing.expectEqual(@as(u32, 2), result.combined_outputs);
    // The id bound covers every id the transform introduced.
    try testing.expect(result.words[3] > SyntheticShader.id_bound);
}

test "clip-distance array elements follow the generated rectangle corner" {
    var source = try SyntheticShader.build(testing.allocator, .{ .clip_distances = true });
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(walkable(result.words));
    // Plain interpolator, gl_Position, and both clip planes. Without array
    // handling this was 2, and the generated corner kept the third vertex's
    // distances even though its position had been mirrored.
    try testing.expectEqual(@as(u32, 4), result.combined_outputs);
    var array_accesses: u32 = 0;
    var offset: usize = 5;
    while (offset < result.words.len) {
        const header = result.words[offset];
        if (opcodeOf(header) == op_access_chain and wordCountOf(header) == 6) array_accesses += 1;
        offset += wordCountOf(header);
    }
    try testing.expectEqual(@as(u32, 8), array_accesses);
}

test "unused trailing CullDistance is removed before rectangle expansion" {
    var source = try SyntheticShader.build(testing.allocator, .{ .cull_distances = true });
    defer source.deinit(testing.allocator);

    const original = try testing.allocator.dupe(u32, source.items);
    defer testing.allocator.free(original);

    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(result.removed_unused_cull_distance);
    try testing.expect(walkable(result.words));
    try testing.expectEqual(@as(u32, 0), countCullDistanceDecorations(result.words));
    try testing.expectEqualSlices(u32, original, source.items);
}

test "active CullDistance remains unchanged and refuses rectangle expansion" {
    var source = try SyntheticShader.build(testing.allocator, .{
        .cull_distances = true,
        .cull_distance_use = true,
    });
    defer source.deinit(testing.allocator);

    const original = try testing.allocator.dupe(u32, source.items);
    defer testing.allocator.free(original);

    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.cull_distance_output, result.refusal);
    try testing.expect(!result.removed_unused_cull_distance);
    try testing.expectEqual(@as(usize, 0), result.words.len);
    try testing.expectEqualSlices(u32, original, source.items);
    try testing.expectEqualStrings("cull-distance-output-metal-unsupported", result.refusal.label());
    const site = result.cull_distance_site orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, SyntheticShader.id_position_var), site.variable);
    try testing.expectEqual(@as(u32, SyntheticShader.id_block), site.interface_type);
    try testing.expectEqual(@as(?u32, 1), site.member_index);
}

test "the renamed entry point emits no module-scope Nop" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    var offset: usize = 5;
    while (offset < result.words.len) {
        const opcode = opcodeOf(result.words[offset]);
        if (opcode == op_function) break;
        try testing.expect(opcode != 0);
        offset += wordCountOf(result.words[offset]);
    }
}

test "vector selections use vector boolean conditions" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    var conditions: [5]u32 = @splat(0);
    var condition_count: usize = 0;
    var vector_selects: usize = 0;
    var offset: usize = 5;
    while (offset < result.words.len) {
        const opcode = opcodeOf(result.words[offset]);
        if (opcode == op_composite_construct and condition_count < conditions.len) {
            conditions[condition_count] = result.words[offset + 2];
            condition_count += 1;
        }
        if (opcode == op_select and result.words[offset + 1] == SyntheticShader.id_vec4) {
            const condition = result.words[offset + 3];
            try testing.expect(std.mem.indexOfScalar(u32, conditions[0..condition_count], condition) != null);
            vector_selects += 1;
        }
        offset += wordCountOf(result.words[offset]);
    }
    try testing.expectEqual(@as(usize, 5), condition_count);
    try testing.expectEqual(@as(usize, 18), vector_selects);
}

test "an ordinary vertex shades once and a rectangle shades all three of its vertices" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);

    // One call on the untagged path, and three on the tagged one: the strip's
    // orientation is chosen from all three shaded positions, so every corner
    // needs all three, not just the derived one.
    try testing.expectEqual(@as(u32, 4), countOpcode(result.words, op_function_call));
    // One selection - tagged or not. Choosing the corner is done with
    // `OpSelect`, which needs no control flow and so no second merge block.
    try testing.expectEqual(@as(u32, 1), countOpcode(result.words, op_selection_merge));
    try testing.expectEqual(@as(u32, 1), countOpcode(result.words, op_branch_conditional));
    // Per output: pick-of-three (2), first-of-three (2) and the derived
    // corner against the picked one (1).
    try testing.expect(countOpcode(result.words, op_select) >= result.combined_outputs * 5);
}

test "the strip orientation is chosen from the shaded positions" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);

    // Three squared edge lengths, each two components subtracted, squared and
    // summed: six extracts, three subtractions, six multiplies. The two
    // comparisons that pick the longest edge, plus the `logical and` Xenia
    // uses for "edge 12 beats both others".
    try testing.expectEqual(@as(u32, 12), countOpcode(result.words, op_composite_extract));
    try testing.expectEqual(@as(u32, 6), countOpcode(result.words, op_f_mul));
    try testing.expectEqual(@as(u32, 3), countOpcode(result.words, op_f_ord_greater_than));
    try testing.expectEqual(@as(u32, 1), countOpcode(result.words, op_logical_and));
}

test "a shader with no position output still expands, on the canonical strip" {
    // Without a position there is no edge to measure. Xenia calls the
    // canonical 0123 strip "most commonly used", so it is the right thing to
    // fall back to - and far better than refusing the expansion outright.
    var source = try SyntheticShader.build(testing.allocator, .{ .position_builtin = false });
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(walkable(result.words));
    // Nothing was measured, so no edge lengths were computed.
    try testing.expectEqual(@as(u32, 0), countOpcode(result.words, op_f_ord_greater_than));
    // The guest body is still shaded three times and the corner still chosen.
    try testing.expectEqual(@as(u32, 4), countOpcode(result.words, op_function_call));
}

test "the tag cannot collide with a guest vertex index" {
    // Xenos vertex indices are 24-bit, so the tag sits well above anything
    // the guest can supply, and clearing it recovers Xenia's encoding.
    try testing.expectEqual(@as(u32, 0x8000_0000), rect_tag);
    const guest_max: u32 = 0x00FF_FFFF;
    try testing.expectEqual(@as(u32, 0), guest_max & rect_tag);
    const encoded: u32 = rect_tag | (7 << 2) | 3;
    try testing.expectEqual(@as(u32, 7), (encoded & ~rect_tag) >> 2);
    try testing.expectEqual(@as(u32, 3), encoded & 3);
}

test "a module this transform cannot read is returned untouched rather than half-rewritten" {
    // Not SPIR-V at all.
    const rubbish = [_]u32{ 0xDEAD_BEEF, 1, 2, 3, 4 };
    try testing.expectEqual(Refusal.not_spirv, (try expand(testing.allocator, &rubbish)).refusal);
    // Too short to carry a header.
    const stub = [_]u32{ magic, 0 };
    try testing.expectEqual(Refusal.not_spirv, (try expand(testing.allocator, &stub)).refusal);

    // A fragment shader has no vertex expansion to do.
    var fragment = try SyntheticShader.build(testing.allocator, .{ .vertex = false });
    defer fragment.deinit(testing.allocator);
    try testing.expectEqual(Refusal.not_vertex, (try expand(testing.allocator, fragment.items)).refusal);

    // A vertex shader that never reads the builtin cannot be expanded, and is
    // left exactly as it arrived.
    var no_builtin = try SyntheticShader.build(testing.allocator, .{ .with_builtin = false });
    defer no_builtin.deinit(testing.allocator);
    const refused = try expand(testing.allocator, no_builtin.items);
    try testing.expectEqual(Refusal.no_vertex_index, refused.refusal);
    try testing.expectEqual(@as(usize, 0), refused.words.len);
}

test "every refusal names itself" {
    // A refusal that cannot be read back is indistinguishable from a silent
    // pass-through, which is how this fallback went unnoticed in Xenia.
    for ([_]Refusal{ .none, .not_spirv, .not_vertex, .no_vertex_index, .vertex_index_shape, .entry_function, .too_many_outputs, .id_space, .already_expanded, .cull_distance_output }) |refusal| {
        try testing.expect(refusal.label().len != 0);
    }
}

/// SPIR-V requires type and constant declarations to be unique: two
/// `OpTypePointer` with the same storage class and pointee are the same type,
/// and a second declaration of one is invalid. A transform that appends
/// blindly produces exactly that, and a validator - or a driver - rejects the
/// module with no clue which pass added it.
fn hasDuplicateDeclarations(allocator: std.mem.Allocator, words: []const u32) !bool {
    var pointers = std.AutoHashMap(u64, void).init(allocator);
    defer pointers.deinit();
    var constants = std.AutoHashMap(u64, void).init(allocator);
    defer constants.deinit();
    var function_types = std.AutoHashMap(u32, void).init(allocator);
    defer function_types.deinit();
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        const opcode = opcodeOf(words[offset]);
        const operands = words[offset + 1 .. offset + count];
        switch (opcode) {
            op_type_pointer => if (operands.len >= 3) {
                const key = (@as(u64, operands[1]) << 32) | operands[2];
                if (pointers.contains(key)) return true;
                try pointers.put(key, {});
            },
            op_constant => if (operands.len >= 3) {
                const key = (@as(u64, operands[0]) << 32) | operands[2];
                if (constants.contains(key)) return true;
                try constants.put(key, {});
            },
            op_type_function => if (operands.len == 2) {
                if (function_types.contains(operands[1])) return true;
                try function_types.put(operands[1], {});
            },
            else => {},
        }
        offset += count;
    }
    return false;
}

test "the transform reuses declarations the module already has" {
    var source = try SyntheticShader.build(testing.allocator, .{ .predeclare = true });
    defer source.deinit(testing.allocator);
    try testing.expect(!try hasDuplicateDeclarations(testing.allocator, source.items));

    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expectEqual(Refusal.none, result.refusal);
    try testing.expect(walkable(result.words));
    // The private pointer type, the void function type and the constant 2 are
    // all already declared; declaring any of them again is invalid SPIR-V.
    try testing.expect(!try hasDuplicateDeclarations(testing.allocator, result.words));
}

test "a module with nothing predeclared also ends up with unique declarations" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expect(!try hasDuplicateDeclarations(testing.allocator, result.words));
}

test "from SPIR-V 1.4 the private stand-in joins the entry point interface" {
    var older = try SyntheticShader.build(testing.allocator, .{});
    defer older.deinit(testing.allocator);
    const before = try expand(testing.allocator, older.items);
    defer testing.allocator.free(before.words);

    var newer = try SyntheticShader.build(testing.allocator, .{ .version_1_4 = true });
    defer newer.deinit(testing.allocator);
    const after = try expand(testing.allocator, newer.items);
    defer testing.allocator.free(after.words);

    try testing.expect(walkable(after.words));
    try testing.expectEqual(
        entryPointInterfaceLength(before.words) + 1,
        entryPointInterfaceLength(after.words),
    );
}

fn entryPointInterfaceLength(words: []const u32) usize {
    var offset: usize = 5;
    while (offset < words.len) {
        const count = wordCountOf(words[offset]);
        if (opcodeOf(words[offset]) == op_entry_point) return count;
        offset += count;
    }
    return 0;
}

test "an execution mode follows the entry point to the new function" {
    var source = try SyntheticShader.build(testing.allocator, .{ .execution_mode = true });
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    try testing.expect(walkable(result.words));

    const target = findEntryPointTarget(result.words).?;
    var offset: usize = 5;
    var checked = false;
    while (offset < result.words.len) {
        const count = wordCountOf(result.words[offset]);
        if (opcodeOf(result.words[offset]) == op_execution_mode) {
            // An execution mode left naming the old function describes an
            // entry point that no longer exists.
            try testing.expectEqual(target, result.words[offset + 1]);
            checked = true;
        }
        offset += count;
    }
    try testing.expect(checked);
}

test "a shader the guest already expanded is refused, so point lists keep working" {
    // Xenia *does* implement kPointListAsTriangleStrip, and its shader
    // decodes the same encoded index. Expanding that a second time would
    // read the point's primitive index as a rectangle's.
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);

    // Splice a shift of the loaded vertex index into the body, which is the
    // shape of the guest's own decode.
    var decoding: std.ArrayList(u32) = .empty;
    defer decoding.deinit(testing.allocator);
    var offset: usize = 0;
    while (offset < source.items.len) {
        const count: usize = if (offset < 5) 1 else wordCountOf(source.items[offset]);
        try decoding.appendSlice(testing.allocator, source.items[offset .. offset + count]);
        if (offset >= 5 and opcodeOf(source.items[offset]) == op_load) {
            try decoding.appendSlice(testing.allocator, &.{
                instructionWord(op_shift_right_logical, 5),
                SyntheticShader.id_int,
                SyntheticShader.id_bound,
                SyntheticShader.id_loaded,
                SyntheticShader.id_loaded,
            });
        }
        offset += count;
    }
    const refused = try expand(testing.allocator, decoding.items);
    try testing.expectEqual(Refusal.already_expanded, refused.refusal);
    try testing.expectEqual(@as(usize, 0), refused.words.len);
}

/// The rectangle expansion's arithmetic in plain Zig, on positions: which
/// vertex starts the strip, and the corner derived for the fourth.
///
/// The emitted SPIR-V computes exactly this, per shaded output. It exists so
/// the formula can be checked numerically - the structural tests above prove
/// the right instructions are present and say nothing about whether they add
/// up to a rectangle, which is how a derived corner displaced by `v[first]`
/// once shipped behind twelve passing tests.
pub fn fourthCorner(v: [3][2]f32) struct { first: u32, corner: [2]f32 } {
    const edge = struct {
        fn len2(a: [2]f32, b: [2]f32) f32 {
            const dx = b[0] - a[0];
            const dy = b[1] - a[1];
            return dx * dx + dy * dy;
        }
    };
    // [0] - edge 12, [1] - edge 20, [2] - edge 01, as Xenia names them.
    const e0 = edge.len2(v[1], v[2]);
    const e1 = edge.len2(v[2], v[0]);
    const e2 = edge.len2(v[0], v[1]);
    const first: u32 = if (e0 > e1 and e0 > e2) 0 else if (e1 > e2) 1 else 2;
    const a = v[(first + 1) % 3];
    const b = v[(first + 2) % 3];
    const f = v[first];
    return .{ .first = first, .corner = .{ (a[0] - f[0]) + b[0], (a[1] - f[1]) + b[1] } };
}

test "the derived corner completes the rectangle in every orientation Xenia names" {
    // Xenia's own three cases from `vulkan_pipeline_cache.cc`, on a unit
    // square with the missing corner at (1,1) each time. The corner opposite
    // the longest edge starts the strip, and the fourth is that corner
    // mirrored across the diagonal.
    const Case = struct { v: [3][2]f32, first: u32 };
    for ([_]Case{
        // 0---1 / 2--[3]: edge 12 is the diagonal, strip 0123.
        .{ .v = .{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 } }, .first = 0 },
        // 1---2 / 0--[3]: edge 20 is the diagonal, strip 1203.
        .{ .v = .{ .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 } }, .first = 1 },
        // 2---0 / 1--[3]: edge 01 is the diagonal, strip 2013.
        .{ .v = .{ .{ 1, 0 }, .{ 0, 1 }, .{ 0, 0 } }, .first = 2 },
    }) |c| {
        const r = fourthCorner(c.v);
        try testing.expectEqual(c.first, r.first);
        try testing.expectEqual([2]f32{ 1, 1 }, r.corner);
    }

    // A full-screen rectangle in clip space, the shape a title background is.
    // The version that subtracted `v[first]` once put this corner at (0, 2):
    // on screen, a rectangle cut in half along its diagonal.
    const screen = fourthCorner(.{ .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 } });
    try testing.expectEqual([2]f32{ 1, 1 }, screen.corner);

    // Not axis aligned, not unit, not at the origin: the corner is still the
    // one that closes the parallelogram.
    const tilted = fourthCorner(.{ .{ 2, 1 }, .{ 5, 2 }, .{ 1, 4 } });
    try testing.expectEqual([2]f32{ 4, 5 }, tilted.corner);
}

test "rectangle corner preserves translated coordinates without cancelling low bits" {
    const large: f32 = 8_388_608;
    const r = fourthCorner(.{ .{ large, large }, .{ large + 1, large }, .{ large, large + 1 } });
    try testing.expectEqual(@as(u32, 0), r.first);
    try testing.expectEqual([2]f32{ large + 1, large + 1 }, r.corner);

    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const expanded = try expand(testing.allocator, source.items);
    defer testing.allocator.free(expanded.words);
    var precise: usize = 0;
    var offset: usize = 5;
    while (offset < expanded.words.len) : (offset += wordCountOf(expanded.words[offset])) {
        if (opcodeOf(expanded.words[offset]) == op_decorate and
            wordCountOf(expanded.words[offset]) == 3 and
            expanded.words[offset + 2] == decoration_no_contraction) precise += 1;
    }
    try testing.expectEqual(@as(usize, expanded.combined_outputs * 2), precise);
}

test "the emitted corner uses Xenia's subtract-then-add evaluation" {
    var source = try SyntheticShader.build(testing.allocator, .{});
    defer source.deinit(testing.allocator);
    const result = try expand(testing.allocator, source.items);
    defer testing.allocator.free(result.words);
    // Three edges of two components are subtracted to measure the diagonal;
    // then each output computes (second - first) + third.
    try testing.expectEqual(@as(u32, 6 + result.combined_outputs), countOpcode(result.words, op_f_sub));
    try testing.expectEqual(@as(u32, 3 + result.combined_outputs), countOpcode(result.words, op_f_add));
}
