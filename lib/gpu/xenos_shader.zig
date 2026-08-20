//! Small, deterministic Xenos shader decoder and source translator.
//!
//! Xenos shaders are clause-based vector programs rather than Vulkan shader
//! modules.  The full Xenia translator remains the authority for every hardware
//! corner case, but Rosette still needs a safe extraction/translation boundary:
//! it must be able to identify a shader, cache it, produce useful diagnostics,
//! and provide a host shader for the simple paths used during bring-up.
//!
//! The decoder below accepts the compact instruction form used by the Rosette
//! bridge (and by tests), preserves modifiers/swizzles, and emits valid MSL
//! expressions for the common ALU and texture operations. Unknown opcodes are
//! retained as comments rather than being silently dropped.

const std = @import("std");

pub const ShaderType = enum(u2) { vertex = 0, pixel = 1, compute = 2, unknown = 3 };

pub const AluOp = enum(u8) {
    add,
    mul,
    mad,
    dp2add,
    dp3,
    dp4,
    rcp,
    rsq,
    log2,
    exp2,
    log_clamped,
    exp_clamped,
    frac,
    trunc,
    floor,
    ceil,
    cndgt,
    cndge,
    cmp,
    max,
    min,
    abs,
    neg,
    kill,
    kill_ne,
    sub,
    select,
    setp,
    bit_and,
    bit_or,
    bit_xor,
    bit_not,
    tex_sample,
    tex_load,
    tex_gather,
    tex_query,
    tex_sample_lod,
    tex_sample_grad,
    ddx,
    ddy,
    export_value,
    _,

    pub fn label(self: AluOp) []const u8 {
        return switch (self) {
            .add => "add",
            .mul => "mul",
            .mad => "mad",
            .dp2add => "dp2add",
            .dp3 => "dp3",
            .dp4 => "dp4",
            .rcp => "rcp",
            .rsq => "rsq",
            .log2 => "log2",
            .exp2 => "exp2",
            .log_clamped => "log_clamped",
            .exp_clamped => "exp_clamped",
            .frac => "frac",
            .trunc => "trunc",
            .floor => "floor",
            .ceil => "ceil",
            .cndgt => "cndgt",
            .cndge => "cndge",
            .cmp => "cmp",
            .max => "max",
            .min => "min",
            .abs => "abs",
            .neg => "neg",
            .kill => "kill",
            .kill_ne => "kill_ne",
            .sub => "sub",
            .select => "select",
            .setp => "setp",
            .bit_and => "and",
            .bit_or => "or",
            .bit_xor => "xor",
            .bit_not => "not",
            .tex_sample => "tex_sample",
            .tex_load => "tex_load",
            .tex_gather => "tex_gather",
            .tex_query => "tex_query",
            .tex_sample_lod => "tex_sample_lod",
            .tex_sample_grad => "tex_sample_grad",
            .ddx => "ddx",
            .ddy => "ddy",
            .export_value => "export",
            _ => "unknown",
        };
    }
};

pub const Operand = struct {
    register: u8 = 0,
    swizzle: [4]u2 = .{ 0, 1, 2, 3 },
    negate: bool = false,
    absolute: bool = false,
    constant: bool = false,
    relative: bool = false,
    address_register: u1 = 0,
};

pub const Instruction = struct {
    op: AluOp = .add,
    destination: u8 = 0,
    sources: [3]Operand = .{ .{}, .{}, .{} },
    source_count: u8 = 2,
    predicate: u8 = 0,
    predicate_enable: bool = false,
    predicate_invert: bool = false,
    export_target: u8 = 0,
    saturate: bool = false,
    kill_if_zero: bool = false,
};

pub const Program = struct {
    shader_type: ShaderType = .unknown,
    instruction_count: u16 = 0,
    export_count: u8 = 0,
    constant_count: u16 = 0,
    pixel_output_depth: bool = false,
    pixel_output_sample_mask: bool = false,
    pixel_output_coverage: bool = false,
    instructions: [256]Instruction = [_]Instruction{.{}} ** 256,
    source_hash: u64 = 0,

    pub fn parse(words: []const u32) ParseError!Program {
        if (words.len < 4) return error.HeaderTooSmall;
        var program: Program = .{};
        program.shader_type = @enumFromInt(@as(u2, @truncate(words[0] & 3)));
        const body_words = @min(words[1] & 0xFFFF, @as(u32, @intCast(words.len - 4)));
        program.export_count = @truncate(words[2] & 0xFF);
        // The compact Rosette shader header reserves the next three bits for
        // pixel-stage system exports.  Xenia's native SPIR-V path does not
        // use this fallback header, but retaining the metadata here makes the
        // fallback capable of expressing depth/sample coverage outputs rather
        // than silently reducing every pixel program to colour only.
        program.pixel_output_depth = (words[2] & (1 << 8)) != 0;
        program.pixel_output_sample_mask = (words[2] & (1 << 9)) != 0;
        program.pixel_output_coverage = (words[2] & (1 << 10)) != 0;
        program.constant_count = @truncate(words[3] & 0xFFFF);
        var cursor: usize = 4;
        var instruction_index: usize = 0;
        while (cursor + 3 < words.len and instruction_index < program.instructions.len and instruction_index * 4 < body_words) : ({
            cursor += 4;
            instruction_index += 1;
        }) {
            const a = words[cursor];
            const b = words[cursor + 1];
            const c = words[cursor + 2];
            const d = words[cursor + 3];
            program.instructions[instruction_index] = decodeInstruction(a, b, c, d);
        }
        program.instruction_count = @intCast(instruction_index);
        program.source_hash = hashWords(words);
        return program;
    }

    pub fn translateMsl(self: *const Program, output: []u8) TranslateError![]const u8 {
        var writer = std.Io.Writer.fixed(output);
        writer.print("// Rosette Xenos shader 0x{x}\n", .{self.source_hash}) catch return error.OutputTooSmall;
        writer.writeAll("#include <metal_stdlib>\nusing namespace metal;\n\n") catch return error.OutputTooSmall;
        writer.writeAll(
            "inline float4 rosette_bit_and(float4 a, float4 b) { return as_type<float4>(as_type<uint4>(a) & as_type<uint4>(b)); }\n" ++
                "inline float4 rosette_bit_or(float4 a, float4 b) { return as_type<float4>(as_type<uint4>(a) | as_type<uint4>(b)); }\n" ++
                "inline float4 rosette_bit_xor(float4 a, float4 b) { return as_type<float4>(as_type<uint4>(a) ^ as_type<uint4>(b)); }\n" ++
                "inline float4 rosette_bit_not(float4 a) { return as_type<float4>(~as_type<uint4>(a)); }\n" ++
                "inline float4 rosette_texture_sample(float4 coordinates, texture2d<float> texture0, sampler sampler0) {\n" ++
                "  if (texture0.get_width() == 0 || texture0.get_height() == 0) return float4(0.0);\n" ++
                "  return texture0.sample(sampler0, coordinates.xy);\n" ++
                "}\n" ++
                "inline float4 rosette_texture_load(float4 coordinates, texture2d<float> texture0) {\n" ++
                "  if (texture0.get_width() == 0 || texture0.get_height() == 0) return float4(0.0);\n" ++
                "  return texture0.read(uint2(max(coordinates.xy, float2(0.0))));\n" ++
                "}\n" ++
                "inline float4 rosette_texture_query(texture2d<float> texture0) {\n" ++
                "  return float4(float(texture0.get_width()), float(texture0.get_height()), float(texture0.get_num_mip_levels()), 0.0);\n" ++
                "}\n" ++
                "inline float4 rosette_texture_sample_lod(float4 coordinates, float lod, texture2d<float> texture0, sampler sampler0) {\n" ++
                "  if (texture0.get_width() == 0 || texture0.get_height() == 0) return float4(0.0);\n" ++
                "  return texture0.sample(sampler0, coordinates.xy, level(lod));\n" ++
                "}\n" ++
                "inline float4 rosette_texture_sample_grad(float4 coordinates, float4 gradient_x, float4 gradient_y, texture2d<float> texture0, sampler sampler0) {\n" ++
                "  if (texture0.get_width() == 0 || texture0.get_height() == 0) return float4(0.0);\n" ++
                "  return texture0.sample(sampler0, coordinates.xy, gradient2d(gradient_x.xy, gradient_y.xy));\n" ++
                "}\n" ++
                "inline float4 rosette_texture_gather(float4 coordinates, texture2d<float> texture0, sampler sampler0) {\n" ++
                "  if (texture0.get_width() == 0 || texture0.get_height() == 0) return float4(0.0);\n" ++
                "  return texture0.gather(sampler0, coordinates.xy, 0u);\n" ++
                "}\n\n",
        ) catch return error.OutputTooSmall;

        const color_count: usize = @max(@as(usize, 1), @min(@as(usize, self.export_count), 8));
        switch (self.shader_type) {
            .vertex => {
                writer.writeAll("struct VertexOut { float4 position [[position]];\n") catch return error.OutputTooSmall;
                for (0..8) |parameter| {
                    writer.print("  float4 param{d} [[user(locn{d})]];\n", .{ parameter, parameter }) catch return error.OutputTooSmall;
                }
                writer.writeAll(
                    "};\nvertex VertexOut main_vertex(texture2d<float> texture0 [[texture(0)]], sampler sampler0 [[sampler(0)]]) {\n",
                ) catch return error.OutputTooSmall;
            },
            .pixel => {
                writer.writeAll("struct FragmentIn {\n") catch return error.OutputTooSmall;
                for (0..8) |parameter| {
                    writer.print("  float4 param{d} [[user(locn{d})]];\n", .{ parameter, parameter }) catch return error.OutputTooSmall;
                }
                writer.writeAll("};\nstruct FragmentOut {\n") catch return error.OutputTooSmall;
                for (0..color_count) |color_index| {
                    writer.print("  float4 color{d} [[color({d})]];\n", .{ color_index, color_index }) catch return error.OutputTooSmall;
                }
                if (self.pixel_output_depth) writer.writeAll("  float depth [[depth(any)]];\n") catch return error.OutputTooSmall;
                if (self.pixel_output_sample_mask) writer.writeAll("  uint sample_mask [[sample_mask]];\n") catch return error.OutputTooSmall;
                if (self.pixel_output_coverage) writer.writeAll("  uint coverage [[coverage]];\n") catch return error.OutputTooSmall;
                writer.writeAll(
                    "};\nfragment FragmentOut main_fragment(FragmentIn input [[stage_in]], texture2d<float> texture0 [[texture(0)]], sampler sampler0 [[sampler(0)]]) {\n",
                ) catch return error.OutputTooSmall;
            },
            .compute => writer.writeAll(
                "kernel void main_compute(texture2d<float> texture0 [[texture(0)]], sampler sampler0 [[sampler(0)]]) {\n",
            ) catch return error.OutputTooSmall,
            .unknown => writer.writeAll(
                "// unknown shader type\nvoid main_unknown(texture2d<float> texture0 [[texture(0)]], sampler sampler0 [[sampler(0)]]) {\n",
            ) catch return error.OutputTooSmall,
        }
        writer.writeAll("  float4 r[128] = {};\n  float4 c[256] = {};\n  bool b[8] = {};\n  float a[2] = {};\n  float4 e[8] = {};\n") catch return error.OutputTooSmall;
        if (self.shader_type == .pixel) {
            for (0..8) |parameter| {
                writer.print("  r[{d}] = input.param{d};\n", .{ parameter + 1, parameter }) catch return error.OutputTooSmall;
            }
        }
        var export_seen: [8]bool = [_]bool{false} ** 8;
        var index: usize = 0;
        while (index < self.instruction_count) : (index += 1) {
            const instruction = self.instructions[index];
            if (instruction.op == .export_value) {
                if (instruction.export_target < export_seen.len) {
                    var source_text: [256]u8 = undefined;
                    const source = operandExpression(instruction.sources[0], &source_text) catch return error.OutputTooSmall;
                    writer.print("  e[{d}] = {s};\n", .{ instruction.export_target, source }) catch return error.OutputTooSmall;
                    export_seen[instruction.export_target] = true;
                }
                continue;
            }
            if (self.shader_type == .pixel and (instruction.op == .kill or instruction.op == .kill_ne)) {
                var kill_source: [256]u8 = undefined;
                const source = operandExpression(instruction.sources[0], &kill_source) catch return error.OutputTooSmall;
                if (instruction.op == .kill) {
                    writer.print("  if (all({s} == float4(0.0))) discard_fragment();\n", .{source}) catch return error.OutputTooSmall;
                } else {
                    writer.print("  if (any({s} != float4(0.0))) discard_fragment();\n", .{source}) catch return error.OutputTooSmall;
                }
                continue;
            }
            var expression: [512]u8 = undefined;
            const expression_text = expressionFor(instruction, &expression) catch return error.OutputTooSmall;
            if (instruction.predicate_enable) {
                writer.print(
                    "  if ({s}b[{d}]) {{\n",
                    .{ if (instruction.predicate_invert) "!" else "", instruction.predicate },
                ) catch return error.OutputTooSmall;
            }
            if (instruction.op == .setp) {
                writer.print("    r[{d}] = {s};\n", .{ instruction.destination, expression_text }) catch return error.OutputTooSmall;
                writer.print("    b[{d}] = any(r[{d}] != float4(0.0));\n", .{ instruction.predicate, instruction.destination }) catch return error.OutputTooSmall;
            } else if (instruction.saturate) {
                writer.print("    r[{d}] = clamp({s}, 0.0, 1.0);\n", .{ instruction.destination, expression_text }) catch return error.OutputTooSmall;
            } else {
                writer.print("    r[{d}] = {s};\n", .{ instruction.destination, expression_text }) catch return error.OutputTooSmall;
            }
            if (self.shader_type == .pixel and instruction.kill_if_zero) {
                writer.print("    if (all(r[{d}] == float4(0.0))) discard_fragment();\n", .{instruction.destination}) catch return error.OutputTooSmall;
            }
            if (instruction.predicate_enable) writer.writeAll("  }\n") catch return error.OutputTooSmall;
        }
        switch (self.shader_type) {
            .vertex => {
                writer.writeAll("  VertexOut out;\n") catch return error.OutputTooSmall;
                writer.print("  out.position = {s};\n", .{if (export_seen[0]) "e[0]" else "r[0]"}) catch return error.OutputTooSmall;
                for (1..8) |parameter| {
                    if (export_seen[parameter]) {
                        writer.print("  out.param{d} = e[{d}];\n", .{ parameter - 1, parameter }) catch return error.OutputTooSmall;
                    } else {
                        writer.print("  out.param{d} = r[{d}];\n", .{ parameter - 1, parameter }) catch return error.OutputTooSmall;
                    }
                }
                writer.writeAll("  return out;\n}\n") catch return error.OutputTooSmall;
            },
            .pixel => {
                writer.writeAll("  FragmentOut out;\n") catch return error.OutputTooSmall;
                for (0..color_count) |color_index| {
                    if (export_seen[color_index]) {
                        writer.print("  out.color{d} = e[{d}];\n", .{ color_index, color_index }) catch return error.OutputTooSmall;
                    } else if (color_index == 0) {
                        writer.print("  out.color{d} = r[0];\n", .{color_index}) catch return error.OutputTooSmall;
                    } else {
                        writer.print("  out.color{d} = float4(0.0);\n", .{color_index}) catch return error.OutputTooSmall;
                    }
                }
                if (self.pixel_output_depth) {
                    writer.print("  out.depth = {s};\n", .{if (export_seen[6]) "e[6].x" else "r[0].z"}) catch return error.OutputTooSmall;
                }
                if (self.pixel_output_sample_mask) {
                    writer.print("  out.sample_mask = {s};\n", .{if (export_seen[7]) "as_type<uint>(e[7].x)" else "0xFFFFffffu"}) catch return error.OutputTooSmall;
                }
                if (self.pixel_output_coverage) {
                    writer.print("  out.coverage = {s};\n", .{if (export_seen[7]) "as_type<uint>(e[7].y)" else "0xFFFFffffu"}) catch return error.OutputTooSmall;
                }
                writer.writeAll("  return out;\n}\n") catch return error.OutputTooSmall;
            },
            else => writer.writeAll("}\n") catch return error.OutputTooSmall,
        }
        return writer.buffered();
    }

    pub fn translateSpirv(self: *const Program, output: []u32) TranslateError![]const u32 {
        const execution_model: u32 = switch (self.shader_type) {
            .vertex => 0,
            .pixel => 4,
            .compute, .unknown => 5,
        };
        // Xenia's Vulkan backend normally supplies the complete SPIR-V module.
        // This fallback still needs to be a real stage when that module is
        // absent: an empty void vertex shader has no Position output and an
        // empty fragment shader writes no colour, so pipeline creation can
        // succeed while every draw remains invisible.  Emit a tiny, valid
        // module with the Vulkan ABI's built-ins and a deterministic colour.
        var builder = SpirvBuilder.init(output);
        try builder.emit(17, &[_]u32{1}); // OpCapability Shader
        try builder.emit(14, &[_]u32{ 0, 1 }); // OpMemoryModel Logical GLSL450

        const void_type = builder.newId();
        const function_type = builder.newId();
        const function_id = builder.newId();

        if (self.shader_type == .vertex) {
            const bool_type = builder.newId();
            const int_type = builder.newId();
            const float_type = builder.newId();
            const vec4_type = builder.newId();
            const input_int_pointer = builder.newId();
            const output_vec4_pointer = builder.newId();
            const input_vertex_index = builder.newId();
            const output_position = builder.newId();
            const zero_int = builder.newId();
            const one_int = builder.newId();
            const zero_float = builder.newId();
            const one_float = builder.newId();
            const negative_one_float = builder.newId();
            const label = builder.newId();
            const vertex_index_value = builder.newId();
            const x_value = builder.newId();
            const x_centered = builder.newId();
            const is_top_vertex = builder.newId();
            const y_value = builder.newId();
            const position = builder.newId();
            try builder.emitEntryPoint(execution_model, function_id, &.{ input_vertex_index, output_position });
            try builder.emit(71, &[_]u32{ input_vertex_index, 11, 42 }); // BuiltIn VertexIndex
            try builder.emit(71, &[_]u32{ output_position, 11, 0 }); // BuiltIn Position
            try builder.emit(19, &[_]u32{void_type}); // OpTypeVoid
            try builder.emit(33, &[_]u32{ function_type, void_type }); // OpTypeFunction
            try builder.emit(20, &[_]u32{bool_type}); // OpTypeBool
            try builder.emit(21, &[_]u32{ int_type, 32, 1 }); // OpTypeInt signed
            try builder.emit(22, &[_]u32{ float_type, 32 }); // OpTypeFloat
            try builder.emit(23, &[_]u32{ vec4_type, float_type, 4 }); // OpTypeVector
            try builder.emit(32, &[_]u32{ input_int_pointer, 1, int_type }); // Input
            try builder.emit(32, &[_]u32{ output_vec4_pointer, 3, vec4_type }); // Output
            try builder.emit(59, &[_]u32{ input_int_pointer, input_vertex_index, 1 }); // OpVariable Input
            try builder.emit(59, &[_]u32{ output_vec4_pointer, output_position, 3 }); // OpVariable Output
            try builder.emit(43, &[_]u32{ int_type, zero_int, 0 });
            try builder.emit(43, &[_]u32{ int_type, one_int, 1 });
            try builder.emit(43, &[_]u32{ float_type, zero_float, 0x0000_0000 });
            try builder.emit(43, &[_]u32{ float_type, one_float, 0x3F80_0000 });
            try builder.emit(43, &[_]u32{ float_type, negative_one_float, 0xBF80_0000 });
            try builder.emit(54, &[_]u32{ void_type, function_id, 0, function_type }); // OpFunction
            try builder.emit(248, &[_]u32{label}); // OpLabel
            try builder.emit(61, &[_]u32{ int_type, vertex_index_value, input_vertex_index }); // OpLoad
            try builder.emit(111, &[_]u32{ float_type, x_value, vertex_index_value }); // OpConvertSToF
            try builder.emit(131, &[_]u32{ float_type, x_centered, x_value, one_float }); // OpFSub
            try builder.emit(170, &[_]u32{ bool_type, is_top_vertex, vertex_index_value, one_int }); // OpIEqual
            try builder.emit(169, &[_]u32{ float_type, y_value, is_top_vertex, one_float, negative_one_float }); // OpSelect
            try builder.emit(80, &[_]u32{ vec4_type, position, x_centered, y_value, zero_float, one_float }); // OpCompositeConstruct
            try builder.emit(62, &[_]u32{ output_position, position }); // OpStore
            try builder.emit(253, &.{}); // OpReturn
            try builder.emit(56, &.{}); // OpFunctionEnd
        } else if (self.shader_type == .pixel) {
            const float_type = builder.newId();
            const vec4_type = builder.newId();
            const output_pointer = builder.newId();
            const output_color = builder.newId();
            const red = builder.newId();
            const green = builder.newId();
            const blue = builder.newId();
            const alpha = builder.newId();
            const color = builder.newId();
            const label = builder.newId();
            try builder.emitEntryPoint(execution_model, function_id, &.{output_color});
            try builder.emit(16, &[_]u32{ function_id, 7 }); // OriginUpperLeft
            try builder.emit(71, &[_]u32{ output_color, 30, 0 }); // Location 0
            try builder.emit(19, &[_]u32{void_type}); // OpTypeVoid
            try builder.emit(33, &[_]u32{ function_type, void_type }); // OpTypeFunction
            try builder.emit(22, &[_]u32{ float_type, 32 });
            try builder.emit(23, &[_]u32{ vec4_type, float_type, 4 });
            try builder.emit(32, &[_]u32{ output_pointer, 3, vec4_type });
            try builder.emit(59, &[_]u32{ output_pointer, output_color, 3 });
            try builder.emit(43, &[_]u32{ float_type, red, 0x3E4C_CCCD });
            try builder.emit(43, &[_]u32{ float_type, green, 0x3E99_999A });
            try builder.emit(43, &[_]u32{ float_type, blue, 0x3ECC_CCCD });
            try builder.emit(43, &[_]u32{ float_type, alpha, 0x3F80_0000 });
            try builder.emit(44, &[_]u32{ vec4_type, color, red, green, blue, alpha }); // OpConstantComposite
            try builder.emit(54, &[_]u32{ void_type, function_id, 0, function_type });
            try builder.emit(248, &[_]u32{label});
            try builder.emit(62, &[_]u32{ output_color, color });
            try builder.emit(253, &.{});
            try builder.emit(56, &.{});
        } else {
            try builder.emitEntryPoint(execution_model, function_id, &.{});
            try builder.emit(16, &[_]u32{ function_id, 17, 1, 1, 1 }); // LocalSize 1,1,1
            try builder.emit(19, &[_]u32{void_type}); // OpTypeVoid
            try builder.emit(33, &[_]u32{ function_type, void_type }); // OpTypeFunction
            try builder.emit(54, &[_]u32{ void_type, function_id, 0, function_type });
            const label = builder.newId();
            try builder.emit(248, &[_]u32{label});
            try builder.emit(253, &.{});
            try builder.emit(56, &.{});
        }
        return builder.finish();
    }
};

pub const ParseError = error{HeaderTooSmall};
pub const TranslateError = error{OutputTooSmall};

const SpirvBuilder = struct {
    words: []u32,
    count: usize = 5,
    next_id: u32 = 1,

    fn init(words: []u32) SpirvBuilder {
        const result = SpirvBuilder{ .words = words };
        if (words.len >= 5) {
            words[0] = 0x0723_0203;
            words[1] = 0x0001_0000;
            words[2] = 0x5253_3358; // RS3X generator marker.
            words[3] = 0;
            words[4] = 0;
        }
        return result;
    }

    fn newId(self: *SpirvBuilder) u32 {
        const result = self.next_id;
        self.next_id += 1;
        return result;
    }

    fn emit(self: *SpirvBuilder, opcode: u16, operands: []const u32) TranslateError!void {
        if (self.count + operands.len + 1 > self.words.len or operands.len + 1 > 0xFFFF) return error.OutputTooSmall;
        self.words[self.count] = (@as(u32, @intCast(operands.len + 1)) << 16) | opcode;
        @memcpy(self.words[self.count + 1 ..][0..operands.len], operands);
        self.count += operands.len + 1;
    }

    fn emitEntryPoint(self: *SpirvBuilder, execution_model: u32, function_id: u32, interfaces: []const u32) TranslateError!void {
        var operands: [8]u32 = undefined;
        operands[0] = execution_model;
        operands[1] = function_id;
        operands[2] = 0x6E69_616D; // "main" packed little-endian.
        operands[3] = 0; // NUL terminator for the SPIR-V string.
        var count: usize = 4;
        for (interfaces) |interface| {
            if (count == operands.len) return error.OutputTooSmall;
            operands[count] = interface;
            count += 1;
        }
        try self.emit(15, operands[0..count]); // OpEntryPoint
    }

    fn finish(self: *SpirvBuilder) TranslateError![]const u32 {
        if (self.words.len < 5) return error.OutputTooSmall;
        self.words[3] = self.next_id;
        return self.words[0..self.count];
    }
};

pub const CacheEntry = struct {
    hash: u64 = 0,
    shader_type: ShaderType = .unknown,
    program: ?Program = null,
    use_tick: u64 = 0,
};

pub const Cache = struct {
    entries: [128]CacheEntry = [_]CacheEntry{.{}} ** 128,
    tick: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,

    pub fn getOrParse(self: *Cache, words: []const u32) ParseError!*const Program {
        const hash = hashWords(words);
        const shader_type: ShaderType = if (words.len == 0) .unknown else @enumFromInt(@as(u2, @truncate(words[0] & 3)));
        self.tick +%= 1;
        for (&self.entries) |*entry| {
            if (entry.hash == hash and entry.shader_type == shader_type and entry.program != null) {
                entry.use_tick = self.tick;
                self.hits +%= 1;
                return &entry.program.?;
            }
        }
        self.misses +%= 1;
        var target: *CacheEntry = &self.entries[0];
        for (&self.entries) |*entry| {
            if (entry.program == null) {
                target = entry;
                break;
            }
            if (entry.use_tick < target.use_tick) target = entry;
        }
        target.* = .{ .hash = hash, .shader_type = shader_type, .program = try Program.parse(words), .use_tick = self.tick };
        return &target.program.?;
    }
};

fn decodeInstruction(a: u32, b: u32, c: u32, d: u32) Instruction {
    var result = Instruction{
        .op = @enumFromInt(@as(u8, @truncate(a & 0x3F))),
        .destination = @truncate((a >> 8) & 0x7F),
        .source_count = @intCast(@min(((a >> 16) & 3) + 1, @as(u32, 3))),
        .predicate = @truncate((a >> 18) & 7),
        .export_target = @truncate((a >> 21) & 7),
        .saturate = ((a >> 24) & 1) != 0,
        .kill_if_zero = ((a >> 25) & 1) != 0,
        .predicate_enable = ((a >> 26) & 1) != 0,
        .predicate_invert = ((a >> 27) & 1) != 0,
    };
    result.sources[0] = decodeOperand(b);
    result.sources[1] = decodeOperand(c);
    result.sources[2] = decodeOperand(d);
    return result;
}

fn decodeOperand(raw: u32) Operand {
    return .{
        .register = @truncate(raw & 0x7F),
        .swizzle = .{
            @truncate((raw >> 8) & 3),
            @truncate((raw >> 10) & 3),
            @truncate((raw >> 12) & 3),
            @truncate((raw >> 14) & 3),
        },
        .negate = ((raw >> 16) & 1) != 0,
        .absolute = ((raw >> 17) & 1) != 0,
        .constant = ((raw >> 18) & 1) != 0,
        .relative = ((raw >> 19) & 1) != 0,
        .address_register = @truncate((raw >> 20) & 1),
    };
}

fn operandExpression(operand: Operand, buffer: []u8) TranslateError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    const swizzles = "xyzw";
    if (operand.negate) writer.writeAll("-(") catch return error.OutputTooSmall;
    if (operand.absolute) writer.writeAll("abs(") catch return error.OutputTooSmall;
    const register_limit: u32 = if (operand.constant) 255 else 127;
    if (operand.relative) {
        writer.print(
            "{s}[uint(clamp(int(a[{d}]) + {d}, 0, {d}))].{c}{c}{c}{c}",
            .{
                if (operand.constant) "c" else "r",
                operand.address_register,
                operand.register,
                register_limit,
                swizzles[operand.swizzle[0]],
                swizzles[operand.swizzle[1]],
                swizzles[operand.swizzle[2]],
                swizzles[operand.swizzle[3]],
            },
        ) catch return error.OutputTooSmall;
    } else {
        writer.print("{s}[{d}].{c}{c}{c}{c}", .{
            if (operand.constant) "c" else "r",
            operand.register,
            swizzles[operand.swizzle[0]],
            swizzles[operand.swizzle[1]],
            swizzles[operand.swizzle[2]],
            swizzles[operand.swizzle[3]],
        }) catch return error.OutputTooSmall;
    }
    if (operand.absolute) writer.writeAll(")") catch return error.OutputTooSmall;
    if (operand.negate) writer.writeAll(")") catch return error.OutputTooSmall;
    return writer.buffered();
}

fn expressionFor(instruction: Instruction, buffer: []u8) TranslateError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    const sink = struct {
        fn all(writer_: *std.Io.Writer, bytes: []const u8) TranslateError!void {
            writer_.writeAll(bytes) catch return error.OutputTooSmall;
        }

        fn print(writer_: *std.Io.Writer, comptime format: []const u8, args: anytype) TranslateError!void {
            writer_.print(format, args) catch return error.OutputTooSmall;
        }
    };
    const source = struct {
        fn write(writer_: anytype, operand: Operand) TranslateError!void {
            var operand_buffer: [256]u8 = undefined;
            const text = operandExpression(operand, &operand_buffer) catch return error.OutputTooSmall;
            writer_.writeAll(text) catch return error.OutputTooSmall;
        }
    };
    switch (instruction.op) {
        .add, .sub, .mul, .max, .min, .bit_and, .bit_or, .bit_xor => {
            if (instruction.op == .max or instruction.op == .min) {
                try sink.print(&writer, "{s}(", .{if (instruction.op == .max) "max" else "min"});
                try source.write(&writer, instruction.sources[0]);
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ")");
                return writer.buffered();
            }
            if (instruction.op == .bit_and or instruction.op == .bit_or or instruction.op == .bit_xor) {
                try sink.print(&writer, "rosette_bit_{s}(", .{switch (instruction.op) {
                    .bit_and => "and",
                    .bit_or => "or",
                    .bit_xor => "xor",
                    else => unreachable,
                }});
                try source.write(&writer, instruction.sources[0]);
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ")");
                return writer.buffered();
            }
            try source.write(&writer, instruction.sources[0]);
            const operator = switch (instruction.op) {
                .add => " + ",
                .sub => " - ",
                .mul => " * ",
                .max, .min, .bit_and, .bit_or, .bit_xor => unreachable,
                else => " + ",
            };
            try sink.all(&writer, operator);
            try source.write(&writer, instruction.sources[1]);
        },
        .mad => {
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, " * ");
            try source.write(&writer, instruction.sources[1]);
            try sink.all(&writer, " + ");
            try source.write(&writer, instruction.sources[2]);
        },
        .dp2add, .dp3, .dp4 => {
            try sink.print(&writer, "float4(dot(", .{});
            try sink.all(&writer, "(");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ").");
            try sink.all(&writer, switch (instruction.op) {
                .dp2add => "xy",
                .dp3 => "xyz",
                .dp4 => "xyzw",
                else => unreachable,
            });
            try sink.all(&writer, ", (");
            try source.write(&writer, instruction.sources[1]);
            try sink.all(&writer, ").");
            try sink.all(&writer, switch (instruction.op) {
                .dp2add => "xy",
                .dp3 => "xyz",
                .dp4 => "xyzw",
                else => unreachable,
            });
            try sink.all(&writer, "))");
            if (instruction.op == .dp2add) {
                try sink.all(&writer, " + ");
                try source.write(&writer, instruction.sources[2]);
            }
        },
        .rcp => {
            try sink.all(&writer, "(1.0 / ");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .rsq => {
            try sink.all(&writer, "rsqrt(");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .abs => {
            try sink.all(&writer, "abs(");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .neg => {
            try sink.all(&writer, "-(");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .floor, .ceil, .trunc, .frac, .log2, .exp2, .log_clamped, .exp_clamped => {
            const function = switch (instruction.op) {
                .floor => "floor",
                .ceil => "ceil",
                .trunc => "trunc",
                .frac => "fract",
                .log2 => "log2",
                .exp2 => "exp2",
                .log_clamped => "log2",
                .exp_clamped => "exp2",
                else => unreachable,
            };
            if (instruction.op == .log_clamped) {
                try sink.print(&writer, "log2(max(abs(", .{});
            } else if (instruction.op == .exp_clamped) {
                try sink.print(&writer, "exp2(clamp(", .{});
            } else {
                try sink.print(&writer, "{s}(", .{function});
            }
            try source.write(&writer, instruction.sources[0]);
            if (instruction.op == .log_clamped) {
                try sink.all(&writer, ", float4(1.0e-30)))");
            } else if (instruction.op == .exp_clamped) {
                try sink.all(&writer, ", float4(-126.0), float4(126.0)))");
            } else {
                try sink.all(&writer, ")");
            }
        },
        .kill, .kill_ne => {
            try sink.all(&writer, "float4(0.0)");
        },
        .tex_sample, .tex_load, .tex_gather, .tex_query, .tex_sample_lod, .tex_sample_grad => {
            const function = switch (instruction.op) {
                .tex_sample => "rosette_texture_sample(",
                .tex_load => "rosette_texture_load(",
                .tex_gather => "rosette_texture_gather(",
                .tex_query => "rosette_texture_query(",
                .tex_sample_lod => "rosette_texture_sample_lod(",
                .tex_sample_grad => "rosette_texture_sample_grad(",
                else => unreachable,
            };
            try sink.all(&writer, function);
            if (instruction.op == .tex_query) {
                try sink.all(&writer, "texture0)");
            } else {
                try source.write(&writer, instruction.sources[0]);
            }
            if (instruction.op == .tex_sample or instruction.op == .tex_gather) {
                try sink.all(&writer, ", texture0, sampler0)");
            } else if (instruction.op == .tex_load) {
                try sink.all(&writer, ", texture0)");
            } else if (instruction.op == .tex_sample_lod) {
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ".x, texture0, sampler0)");
            } else if (instruction.op == .tex_sample_grad) {
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[2]);
                try sink.all(&writer, ", texture0, sampler0)");
            }
        },
        .ddx, .ddy => {
            try sink.print(&writer, "{s}(", .{if (instruction.op == .ddx) "dfdx" else "dfdy"});
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .cndgt, .cndge, .cmp, .select, .setp => {
            const function = switch (instruction.op) {
                .cndgt => ">",
                .cndge => ">=",
                .cmp => "==",
                .select, .setp => "!=",
                else => unreachable,
            };
            if (instruction.op == .select or instruction.op == .setp) {
                try sink.all(&writer, "select(");
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ", ");
                try source.write(&writer, instruction.sources[2]);
                try sink.print(&writer, ", ", .{});
                try source.write(&writer, instruction.sources[0]);
                try sink.print(&writer, " {s} float4(0.0))", .{function});
            } else {
                try sink.all(&writer, "select(float4(0.0), float4(1.0), ");
                try source.write(&writer, instruction.sources[0]);
                try sink.print(&writer, " {s} ", .{function});
                try source.write(&writer, instruction.sources[1]);
                try sink.all(&writer, ")");
            }
        },
        .bit_not => {
            try sink.all(&writer, "rosette_bit_not(");
            try source.write(&writer, instruction.sources[0]);
            try sink.all(&writer, ")");
        },
        .export_value => try sink.all(&writer, "r[0]"),
        else => try sink.all(&writer, "float4(0.0) /* unsupported Xenos op */"),
    }
    return writer.buffered();
}

// Metal has no bitwise operators on floating-point vectors. Xenos ALU
// registers are bit-preserving 128-bit values, so reinterpret the lanes as
// uint4, perform the operation, and reinterpret them back.
//
// These helpers are emitted into every diagnostic shader by translateMsl.

fn hashWords(words: []const u32) u64 {
    var hasher = std.hash.Wyhash.init(0x5845_4E4F_535F_5348);
    hasher.update(std.mem.sliceAsBytes(words));
    return hasher.final();
}

test "shader decoder preserves the program header and emits MSL" {
    const add = @as(u32, @intFromEnum(AluOp.add));
    const words = [_]u32{
        0,                          4, 1, 16,
        add | (0 << 8) | (1 << 16), 1, 2, 3,
    };
    var program = try Program.parse(&words);
    try std.testing.expectEqual(ShaderType.vertex, program.shader_type);
    try std.testing.expectEqual(@as(u16, 1), program.instruction_count);
    var output: [4096]u8 = undefined;
    const source = try program.translateMsl(&output);
    try std.testing.expect(std.mem.indexOf(u8, source, "r[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "metal_stdlib") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "main_vertex") != null);
    var spirv: [128]u32 = undefined;
    const module = try program.translateSpirv(&spirv);
    try std.testing.expect(module.len > 8);
    try std.testing.expectEqual(@as(u32, 0x0723_0203), module[0]);
}

test "shader cache returns the same parsed program for the same binary" {
    const words = [_]u32{ 1, 0, 0, 0 };
    var cache: Cache = .{};
    const first = try cache.getOrParse(&words);
    const second = try cache.getOrParse(&words);
    try std.testing.expectEqual(@intFromPtr(first), @intFromPtr(second));
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
}

test "shader fallback emits resources predicates relative registers and MRT exports" {
    var program: Program = .{
        .shader_type = .pixel,
        .export_count = 2,
        .instruction_count = 4,
    };
    program.instructions[0] = .{
        .op = .tex_sample,
        .destination = 127,
        .sources = .{ .{ .register = 2 }, .{}, .{} },
    };
    program.instructions[1] = .{
        .op = .setp,
        .destination = 3,
        .predicate = 1,
        .sources = .{ .{ .register = 127 }, .{ .register = 4 }, .{ .register = 5 } },
    };
    program.instructions[2] = .{
        .op = .add,
        .destination = 6,
        .predicate = 1,
        .predicate_enable = true,
        .sources = .{
            .{ .register = 4, .relative = true, .address_register = 1 },
            .{ .register = 6, .constant = true },
            .{},
        },
    };
    program.instructions[3] = .{
        .op = .export_value,
        .export_target = 1,
        .sources = .{ .{ .register = 6 }, .{}, .{} },
    };
    var output: [8192]u8 = undefined;
    const source = try program.translateMsl(&output);
    try std.testing.expect(std.mem.indexOf(u8, source, "texture2d<float> texture0") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "color1 [[color(1)]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "r[128]") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "a[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "b[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "e[1]") != null);
}

test "shader fallback emits explicit LOD gradients gather and system outputs" {
    var program: Program = .{
        .shader_type = .pixel,
        .export_count = 1,
        .pixel_output_depth = true,
        .pixel_output_sample_mask = true,
        .pixel_output_coverage = true,
        .instruction_count = 6,
    };
    program.instructions[0] = .{ .op = .tex_sample_lod, .destination = 0, .sources = .{ .{ .register = 1 }, .{ .register = 2 }, .{} } };
    program.instructions[1] = .{ .op = .tex_sample_grad, .destination = 1, .sources = .{ .{ .register = 1 }, .{ .register = 2 }, .{ .register = 3 } } };
    program.instructions[2] = .{ .op = .tex_gather, .destination = 2, .sources = .{ .{ .register = 1 }, .{}, .{} } };
    program.instructions[3] = .{ .op = .ddx, .destination = 3, .sources = .{ .{ .register = 1 }, .{}, .{} } };
    program.instructions[4] = .{ .op = .ddy, .destination = 4, .sources = .{ .{ .register = 1 }, .{}, .{} } };
    program.instructions[5] = .{ .op = .export_value, .export_target = 6, .sources = .{ .{ .register = 3 }, .{}, .{} } };
    var output: [12288]u8 = undefined;
    const source = try program.translateMsl(&output);
    try std.testing.expect(std.mem.indexOf(u8, source, "level(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "gradient2d(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, ".gather(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "dfdx(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "depth(any)") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "sample_mask") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "coverage") != null);
}
