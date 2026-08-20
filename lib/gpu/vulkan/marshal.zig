//! Turning a guest Vulkan create-info into one a host driver can dereference.
//!
//! A `VkDescriptorSetLayoutCreateInfo` is thirty-two bytes and only sixteen of
//! them are safe to hand to a real driver. The rest is `pBindings` — a pointer
//! into the *guest's* address space — and the driver dereferences it as a host
//! pointer. There is no error path: MoltenVK reads whatever is at that host
//! address and the process dies with no diagnostics, mid-call, which is exactly
//! how the forwarding layer's first real create behaved.
//!
//! The same hazard is in almost every structure Vulkan takes:
//!
//!   * **Array pointers.** `pBindings`, `pSetLayouts`, `pAttachments`,
//!     `pPoolSizes`, `pCode`, `pQueueFamilyIndices`. Guest addresses, all of
//!     them.
//!   * **Handles.** `VkImageView::image`, `VkFramebuffer::renderPass`,
//!     `pSetLayouts[i]`. These hold the *synthetic* handles the modelled layer
//!     minted, which are not real driver objects and are frequently shaped like
//!     pointers — so passing one through is the same crash with a different
//!     address.
//!   * **`pNext`.** A guest pointer to a chain the driver will walk.
//!
//! ## The gate is the safety property
//!
//! Every structure here is described by a `Plan` that accounts for *every*
//! pointer and handle it contains. A structure with no plan is not marshalled
//! and therefore **not forwarded** — the caller keeps the modelled path instead
//! of handing raw guest pointers to a driver. That is the invariant worth
//! having: adding a structure to the real path requires describing it first,
//! and forgetting one cannot crash the process, it can only leave that object
//! modelled.
//!
//! Offsets come from `extern struct` definitions and `@offsetOf` rather than
//! from literals. A hand-counted offset that is wrong by four bytes produces a
//! driver reading a length out of a flags field, which is a crash that looks
//! like a driver bug.

const std = @import("std");

/// Scratch space for translated arrays, owned by the caller for the duration of
/// one call. Fixed rather than allocated: this runs on an import path, and the
/// sizes involved are small and bounded by what a create-info can reference.
// Xenia's translated SPIR-V modules and pipeline-cache blobs can exceed the
// small bring-up payloads used by the descriptor and render-pass paths. Keep
// the arena bounded, but large enough for a real Halo shader/module while it
// is being copied out of guest memory.
pub const scratch_bytes: usize = 256 * 1024;

pub const Scratch = struct {
    buffer: [scratch_bytes]u8 align(16) = undefined,
    used: usize = 0,

    pub fn reset(self: *Scratch) void {
        self.used = 0;
    }

    /// Reserve aligned space. Returns null when exhausted, which the caller
    /// must treat as "do not forward" rather than "forward a short array".
    pub fn alloc(self: *Scratch, size: usize) ?[]u8 {
        const aligned = std.mem.alignForward(usize, self.used, 16);
        if (aligned + size > self.buffer.len) return null;
        self.used = aligned + size;
        return self.buffer[aligned .. aligned + size];
    }
};

/// What a handle field refers to, so the caller can look it up in the right
/// map. The marshaller never owns the maps; it asks.
pub const HandleKind = enum(u8) {
    descriptor_set_layout,
    render_pass,
    image,
    image_view,
    sampler,
    buffer,
    pipeline_layout,

    pub fn label(self: HandleKind) []const u8 {
        return switch (self) {
            .descriptor_set_layout => "descriptor_set_layout",
            .render_pass => "render_pass",
            .image => "image",
            .image_view => "image_view",
            .sampler => "sampler",
            .buffer => "buffer",
            .pipeline_layout => "pipeline_layout",
        };
    }
};

/// Resolve a synthetic handle to the real driver object, or null when the
/// mapping does not exist. A missing mapping is fatal to the call and must not
/// be papered over with a zero: `VK_NULL_HANDLE` is meaningful in some fields
/// and catastrophic in others.
pub const Resolver = struct {
    context: *anyopaque,
    lookup: *const fn (context: *anyopaque, kind: HandleKind, synthetic: u64) ?u64,

    pub fn resolve(self: Resolver, kind: HandleKind, synthetic: u64) ?u64 {
        return self.lookup(self.context, kind, synthetic);
    }
};

/// A pointer-to-array field: a count and a pointer, with a fixed element size.
pub const ArrayField = struct {
    count_offset: usize,
    pointer_offset: usize,
    element_size: usize,
    /// When set, each element is an 8-byte handle needing translation.
    element_handle: ?HandleKind = null,
    /// Bytes into each element that must be zero for the element to be safe to
    /// copy verbatim. Used for nested pointers this layer does not follow —
    /// a non-zero value there means the structure is refused rather than
    /// silently stripped, because stripping changes what the caller asked for.
    forbidden_pointer_offset: ?usize = null,
    /// A second-level handle array hanging off each element.
    ///
    /// `VkDescriptorSetLayoutBinding::pImmutableSamplers` is the case that
    /// forced this: the presenter's very first descriptor set layout uses one,
    /// so refusing nested arrays outright would leave the first structure of
    /// the whole bring-up permanently modelled. Its length is not its own
    /// field — it is the element's `descriptorCount`, which is why the count
    /// offset is expressed relative to the element.
    nested: ?NestedHandleArray = null,
    /// When set, the "count" is a byte length rather than an element count.
    count_is_bytes: bool = false,
};

pub const NestedHandleArray = struct {
    /// Offset within the element of the pointer to the handle array.
    pointer_offset: usize,
    /// Offset within the element of the count governing that array.
    count_offset: usize,
    kind: HandleKind,
};

/// A bare handle field inside the structure.
pub const HandleField = struct {
    offset: usize,
    kind: HandleKind,
    /// Whether a zero (VK_NULL_HANDLE) is legitimate here.
    nullable: bool = false,
};

pub const max_arrays = 3;
pub const max_handles = 2;

pub const Plan = struct {
    name: []const u8,
    size: usize,
    arrays: [max_arrays]?ArrayField = .{ null, null, null },
    handles: [max_handles]?HandleField = .{ null, null },
};

/// Why a structure was not marshalled. Each value is a different thing to do
/// about it, and every one of them means "keep the modelled path".
pub const Refusal = enum(u8) {
    /// No plan describes this structure. The default, and the reason a
    /// forgotten structure cannot crash the process.
    no_plan,
    /// The guest structure is not readable at the address given.
    unreadable,
    /// An array the plan describes is not readable.
    array_unreadable,
    /// Scratch space ran out.
    scratch_exhausted,
    /// A handle in the structure has no real counterpart.
    unresolved_handle,
    /// An element contains a nested pointer this layer does not follow.
    nested_pointer,

    pub fn label(self: Refusal) []const u8 {
        return switch (self) {
            .no_plan => "no_plan",
            .unreadable => "unreadable",
            .array_unreadable => "array_unreadable",
            .scratch_exhausted => "scratch_exhausted",
            .unresolved_handle => "unresolved_handle",
            .nested_pointer => "nested_pointer",
        };
    }

    pub fn meaning(self: Refusal) []const u8 {
        return switch (self) {
            .no_plan => "no plan describes this structure, so nothing accounts for the pointers inside it. Forwarding it would hand the driver guest addresses; the modelled path is kept instead",
            .unreadable => "the guest structure is not readable at the address given, so there is nothing to translate",
            .array_unreadable => "an array the structure points at is not readable in guest memory. The count and the pointer disagree with what is mapped",
            .scratch_exhausted => "the translated arrays do not fit in the scratch arena. Forwarding a truncated array would be worse than not forwarding",
            .unresolved_handle => "a handle inside the structure has no real counterpart. The object it names was never created on the real device, so the call cannot mean what it says",
            .nested_pointer => "an element contains a nested pointer this layer does not follow. Stripping it would change what the caller asked for, so the structure is refused instead",
        };
    }
};

// ---------------------------------------------------------------------------
// Structure layouts. Defined as extern structs so offsets are computed rather
// than counted — a hand-written offset that is wrong by four bytes makes a
// driver read a length out of a flags field.
// ---------------------------------------------------------------------------

pub const DescriptorSetLayoutCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    binding_count: u32 = 0,
    bindings: ?*const anyopaque = null,
};

pub const DescriptorSetLayoutBinding = extern struct {
    binding: u32 = 0,
    descriptor_type: u32 = 0,
    descriptor_count: u32 = 0,
    stage_flags: u32 = 0,
    immutable_samplers: ?*const anyopaque = null,
};

pub const PipelineLayoutCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    set_layout_count: u32 = 0,
    set_layouts: ?*const anyopaque = null,
    push_constant_range_count: u32 = 0,
    push_constant_ranges: ?*const anyopaque = null,
};

pub const PushConstantRange = extern struct {
    stage_flags: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
};

pub const DescriptorPoolCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    max_sets: u32 = 0,
    pool_size_count: u32 = 0,
    pool_sizes: ?*const anyopaque = null,
};

pub const DescriptorPoolSize = extern struct {
    descriptor_type: u32 = 0,
    descriptor_count: u32 = 0,
};

pub const ImageViewCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    image: u64 = 0,
    view_type: u32 = 0,
    format: u32 = 0,
    components: [4]u32 = .{ 0, 0, 0, 0 },
    subresource_range: [5]u32 = .{ 0, 0, 0, 0, 0 },
};

pub const FramebufferCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    render_pass: u64 = 0,
    attachment_count: u32 = 0,
    attachments: ?*const anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,
    layers: u32 = 0,
};

pub const BufferViewCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    buffer: u64 = 0,
    format: u32 = 0,
    offset: u64 = 0,
    range: u64 = 0,
};

/// The render-pass structures are the first Vulkan create-info family whose
/// pointers nest more than one level deep. A generic one-array plan cannot
/// describe them without either dropping fields or handing guest pointers to
/// the driver, so they have a dedicated bounded marshalling routine below.
pub const RenderPassCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    attachment_count: u32 = 0,
    attachments: ?*const anyopaque = null,
    subpass_count: u32 = 0,
    subpasses: ?*const anyopaque = null,
    dependency_count: u32 = 0,
    dependencies: ?*const anyopaque = null,
};

pub const AttachmentDescription = extern struct {
    flags: u32 = 0,
    format: u32 = 0,
    samples: u32 = 0,
    load_op: u32 = 0,
    store_op: u32 = 0,
    stencil_load_op: u32 = 0,
    stencil_store_op: u32 = 0,
    initial_layout: u32 = 0,
    final_layout: u32 = 0,
};

pub const AttachmentReference = extern struct {
    attachment: u32 = 0,
    layout: u32 = 0,
};

pub const SubpassDescription = extern struct {
    flags: u32 = 0,
    pipeline_bind_point: u32 = 0,
    input_attachment_count: u32 = 0,
    input_attachments: ?*const anyopaque = null,
    color_attachment_count: u32 = 0,
    color_attachments: ?*const anyopaque = null,
    resolve_attachments: ?*const anyopaque = null,
    depth_stencil_attachment: ?*const anyopaque = null,
    preserve_attachment_count: u32 = 0,
    preserve_attachments: ?*const anyopaque = null,
};

pub const SubpassDependency = extern struct {
    src_subpass: u32 = 0,
    dst_subpass: u32 = 0,
    src_stage_mask: u32 = 0,
    dst_stage_mask: u32 = 0,
    src_access_mask: u32 = 0,
    dst_access_mask: u32 = 0,
    dependency_flags: u32 = 0,
};

pub const ShaderModuleCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    code_size: usize = 0,
    code: ?*const anyopaque = null,
};

pub const SamplerCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    mag_filter: u32 = 0,
    min_filter: u32 = 0,
    mipmap_mode: u32 = 0,
    address_mode_u: u32 = 0,
    address_mode_v: u32 = 0,
    address_mode_w: u32 = 0,
    mip_lod_bias: f32 = 0,
    anisotropy_enable: u32 = 0,
    max_anisotropy: f32 = 0,
    compare_enable: u32 = 0,
    compare_op: u32 = 0,
    min_lod: f32 = 0,
    max_lod: f32 = 0,
    border_color: u32 = 0,
    unnormalized_coordinates: u32 = 0,
};

pub const ImageCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    image_type: u32 = 0,
    format: u32 = 0,
    extent: [3]u32 = .{ 0, 0, 0 },
    mip_levels: u32 = 0,
    array_layers: u32 = 0,
    samples: u32 = 0,
    tiling: u32 = 0,
    usage: u32 = 0,
    sharing_mode: u32 = 0,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?*const anyopaque = null,
    initial_layout: u32 = 0,
};

pub const BufferCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    size: u64 = 0,
    usage: u32 = 0,
    sharing_mode: u32 = 0,
    queue_family_index_count: u32 = 0,
    queue_family_indices: ?*const anyopaque = null,
};

/// `VkCommandPoolCreateInfo`, `VkFenceCreateInfo`, `VkSemaphoreCreateInfo` and
/// `VkEventCreateInfo` share a shape: a type, a chain pointer, flags, and at
/// most one scalar. Nothing inside them points anywhere, so the only unsafe
/// field is `pNext` — which every plan clears.
pub const FlagsOnlyCreateInfo = extern struct {
    s_type: u32 = 0,
    p_next: ?*const anyopaque = null,
    flags: u32 = 0,
    queue_family_index: u32 = 0,
};

/// The structures the real path is allowed to carry, and everything inside them
/// that is not plain data.
pub fn planFor(name: []const u8) ?Plan {
    if (std.mem.eql(u8, name, "vkCreateSampler")) {
        // Plain data throughout: nothing but scalars after pNext.
        return .{ .name = name, .size = @sizeOf(SamplerCreateInfo) };
    }
    if (std.mem.eql(u8, name, "vkCreateDescriptorSetLayout")) {
        return .{
            .name = name,
            .size = @sizeOf(DescriptorSetLayoutCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(DescriptorSetLayoutCreateInfo, "binding_count"),
                    .pointer_offset = @offsetOf(DescriptorSetLayoutCreateInfo, "bindings"),
                    .element_size = @sizeOf(DescriptorSetLayoutBinding),
                    // Immutable samplers are a second array hanging off each
                    // binding, governed by that binding's own descriptorCount.
                    // The presenter's first descriptor set layout uses one, so
                    // this is not an edge case to refuse — it is the first
                    // structure of the bring-up.
                    .nested = .{
                        .pointer_offset = @offsetOf(DescriptorSetLayoutBinding, "immutable_samplers"),
                        .count_offset = @offsetOf(DescriptorSetLayoutBinding, "descriptor_count"),
                        .kind = .sampler,
                    },
                },
                null,
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreatePipelineLayout")) {
        return .{
            .name = name,
            .size = @sizeOf(PipelineLayoutCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(PipelineLayoutCreateInfo, "set_layout_count"),
                    .pointer_offset = @offsetOf(PipelineLayoutCreateInfo, "set_layouts"),
                    .element_size = @sizeOf(u64),
                    .element_handle = .descriptor_set_layout,
                },
                .{
                    .count_offset = @offsetOf(PipelineLayoutCreateInfo, "push_constant_range_count"),
                    .pointer_offset = @offsetOf(PipelineLayoutCreateInfo, "push_constant_ranges"),
                    .element_size = @sizeOf(PushConstantRange),
                },
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateDescriptorPool")) {
        return .{
            .name = name,
            .size = @sizeOf(DescriptorPoolCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(DescriptorPoolCreateInfo, "pool_size_count"),
                    .pointer_offset = @offsetOf(DescriptorPoolCreateInfo, "pool_sizes"),
                    .element_size = @sizeOf(DescriptorPoolSize),
                },
                null,
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateImageView")) {
        return .{
            .name = name,
            .size = @sizeOf(ImageViewCreateInfo),
            .handles = .{
                .{ .offset = @offsetOf(ImageViewCreateInfo, "image"), .kind = .image },
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateFramebuffer")) {
        return .{
            .name = name,
            .size = @sizeOf(FramebufferCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(FramebufferCreateInfo, "attachment_count"),
                    .pointer_offset = @offsetOf(FramebufferCreateInfo, "attachments"),
                    .element_size = @sizeOf(u64),
                    .element_handle = .image_view,
                },
                null,
                null,
            },
            .handles = .{
                .{ .offset = @offsetOf(FramebufferCreateInfo, "render_pass"), .kind = .render_pass },
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateBufferView")) {
        return .{
            .name = name,
            .size = @sizeOf(BufferViewCreateInfo),
            .handles = .{
                .{ .offset = @offsetOf(BufferViewCreateInfo, "buffer"), .kind = .buffer },
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateShaderModule")) {
        return .{
            .name = name,
            .size = @sizeOf(ShaderModuleCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(ShaderModuleCreateInfo, "code_size"),
                    .pointer_offset = @offsetOf(ShaderModuleCreateInfo, "code"),
                    .element_size = 1,
                    .count_is_bytes = true,
                },
                null,
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateImage")) {
        return .{
            .name = name,
            .size = @sizeOf(ImageCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(ImageCreateInfo, "queue_family_index_count"),
                    .pointer_offset = @offsetOf(ImageCreateInfo, "queue_family_indices"),
                    .element_size = @sizeOf(u32),
                },
                null,
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateBuffer")) {
        return .{
            .name = name,
            .size = @sizeOf(BufferCreateInfo),
            .arrays = .{
                .{
                    .count_offset = @offsetOf(BufferCreateInfo, "queue_family_index_count"),
                    .pointer_offset = @offsetOf(BufferCreateInfo, "queue_family_indices"),
                    .element_size = @sizeOf(u32),
                },
                null,
                null,
            },
        };
    }
    if (std.mem.eql(u8, name, "vkCreateCommandPool") or
        std.mem.eql(u8, name, "vkCreateFence") or
        std.mem.eql(u8, name, "vkCreateSemaphore") or
        std.mem.eql(u8, name, "vkCreateEvent"))
    {
        return .{ .name = name, .size = @sizeOf(FlagsOnlyCreateInfo) };
    }
    // Everything else — render passes above all, whose sub-structures carry
    // further arrays of their own — has no plan and is therefore not forwarded.
    return null;
}

pub const Result = union(enum) {
    /// A host-ready structure, valid until the scratch is reset.
    ready: []u8,
    refused: Refusal,
};

const ArrayCopy = union(enum) {
    ready: []u8,
    refused: Refusal,
};

fn copyArray(
    scratch: *Scratch,
    context: *anyopaque,
    read: *const fn (context: *anyopaque, address: u64, length: u64) ?[]const u8,
    pointer: u64,
    count: u32,
    element_size: usize,
) ArrayCopy {
    if (count == 0 or pointer == 0) return .{ .refused = .array_unreadable };
    const bytes = std.math.mul(u64, count, @as(u64, @intCast(element_size))) catch
        return .{ .refused = .array_unreadable };
    if (bytes > std.math.maxInt(usize)) return .{ .refused = .scratch_exhausted };
    const source = read(context, pointer, bytes) orelse return .{ .refused = .array_unreadable };
    const target = scratch.alloc(@intCast(bytes)) orelse return .{ .refused = .scratch_exhausted };
    @memcpy(target, source[0..@intCast(bytes)]);
    return .{ .ready = target };
}

/// Marshal VkRenderPassCreateInfo and all of the arrays nested below its
/// subpasses. Every pointer in the resulting graph points into `scratch`, and
/// every attachment reference names a plain index rather than a dispatchable
/// Vulkan object, so no synthetic handle translation is needed here.
pub fn marshalRenderPass(
    guest_address: u64,
    scratch: *Scratch,
    resolver: Resolver,
    context: *anyopaque,
    read: *const fn (context: *anyopaque, address: u64, length: u64) ?[]const u8,
) Result {
    _ = resolver;
    const source = read(context, guest_address, @sizeOf(RenderPassCreateInfo)) orelse
        return .{ .refused = .unreadable };
    const target = scratch.alloc(@sizeOf(RenderPassCreateInfo)) orelse
        return .{ .refused = .scratch_exhausted };
    @memcpy(target, source);
    @memset(target[8..16], 0);

    const root = @as(*RenderPassCreateInfo, @ptrCast(@alignCast(target.ptr)));
    if (root.attachment_count != 0) {
        const copy = copyArray(scratch, context, read, @intFromPtr(root.attachments orelse return .{ .refused = .array_unreadable }), root.attachment_count, @sizeOf(AttachmentDescription));
        switch (copy) {
            .ready => |bytes| root.attachments = @ptrCast(bytes.ptr),
            .refused => |refusal| return .{ .refused = refusal },
        }
    } else root.attachments = null;

    if (root.subpass_count != 0) {
        const subpass_pointer = @intFromPtr(root.subpasses orelse return .{ .refused = .array_unreadable });
        const copy = copyArray(scratch, context, read, subpass_pointer, root.subpass_count, @sizeOf(SubpassDescription));
        const subpass_bytes = switch (copy) {
            .ready => |bytes| bytes,
            .refused => |refusal| return .{ .refused = refusal },
        };
        root.subpasses = @ptrCast(subpass_bytes.ptr);
        const subpasses: []SubpassDescription = @as([*]SubpassDescription, @ptrCast(@alignCast(subpass_bytes.ptr)))[0..root.subpass_count];
        for (subpasses) |*subpass| {
            const input_pointer = if (subpass.input_attachments) |pointer| @intFromPtr(pointer) else 0;
            if (subpass.input_attachment_count != 0) {
                const input = copyArray(scratch, context, read, input_pointer, subpass.input_attachment_count, @sizeOf(AttachmentReference));
                switch (input) {
                    .ready => |bytes| subpass.input_attachments = @ptrCast(bytes.ptr),
                    .refused => |refusal| return .{ .refused = refusal },
                }
            } else subpass.input_attachments = null;

            const color_pointer = if (subpass.color_attachments) |pointer| @intFromPtr(pointer) else 0;
            if (subpass.color_attachment_count != 0) {
                const color = copyArray(scratch, context, read, color_pointer, subpass.color_attachment_count, @sizeOf(AttachmentReference));
                switch (color) {
                    .ready => |bytes| subpass.color_attachments = @ptrCast(bytes.ptr),
                    .refused => |refusal| return .{ .refused = refusal },
                }
            } else subpass.color_attachments = null;

            const resolve_pointer = if (subpass.resolve_attachments) |pointer| @intFromPtr(pointer) else 0;
            if (subpass.color_attachment_count != 0 and resolve_pointer != 0) {
                const resolve = copyArray(scratch, context, read, resolve_pointer, subpass.color_attachment_count, @sizeOf(AttachmentReference));
                switch (resolve) {
                    .ready => |bytes| subpass.resolve_attachments = @ptrCast(bytes.ptr),
                    .refused => |refusal| return .{ .refused = refusal },
                }
            } else subpass.resolve_attachments = null;

            const depth_pointer = if (subpass.depth_stencil_attachment) |pointer| @intFromPtr(pointer) else 0;
            if (depth_pointer != 0) {
                const depth = copyArray(scratch, context, read, depth_pointer, 1, @sizeOf(AttachmentReference));
                switch (depth) {
                    .ready => |bytes| subpass.depth_stencil_attachment = @ptrCast(bytes.ptr),
                    .refused => |refusal| return .{ .refused = refusal },
                }
            } else subpass.depth_stencil_attachment = null;

            const preserve_pointer = if (subpass.preserve_attachments) |pointer| @intFromPtr(pointer) else 0;
            if (subpass.preserve_attachment_count != 0) {
                const preserve = copyArray(scratch, context, read, preserve_pointer, subpass.preserve_attachment_count, @sizeOf(u32));
                switch (preserve) {
                    .ready => |bytes| subpass.preserve_attachments = @ptrCast(bytes.ptr),
                    .refused => |refusal| return .{ .refused = refusal },
                }
            } else subpass.preserve_attachments = null;
        }
    } else root.subpasses = null;

    if (root.dependency_count != 0) {
        const dependency_pointer = @intFromPtr(root.dependencies orelse return .{ .refused = .array_unreadable });
        const dependencies = copyArray(scratch, context, read, dependency_pointer, root.dependency_count, @sizeOf(SubpassDependency));
        switch (dependencies) {
            .ready => |bytes| root.dependencies = @ptrCast(bytes.ptr),
            .refused => |refusal| return .{ .refused = refusal },
        }
    } else root.dependencies = null;

    return .{ .ready = target };
}

/// Read a guest create-info and produce one a host driver can dereference.
///
/// `read` hands back a readable view of guest memory, or null. Passing it as a
/// callback keeps this module free of any dependency on the process model,
/// which is what lets it be tested against plain buffers.
pub fn marshal(
    plan: Plan,
    guest_address: u64,
    scratch: *Scratch,
    resolver: Resolver,
    context: *anyopaque,
    read: *const fn (context: *anyopaque, address: u64, length: u64) ?[]const u8,
) Result {
    const source = read(context, guest_address, plan.size) orelse return .{ .refused = .unreadable };
    const target = scratch.alloc(plan.size) orelse return .{ .refused = .scratch_exhausted };
    @memcpy(target, source[0..plan.size]);

    // `pNext` is a guest pointer to a chain the driver would walk. Always at
    // offset 8 in every Vulkan structure, and always cleared: this layer
    // forwards no extension chains.
    @memset(target[8..16], 0);

    for (plan.handles) |maybe_handle| {
        const field = maybe_handle orelse continue;
        const synthetic = std.mem.readInt(u64, target[field.offset..][0..8], .little);
        if (synthetic == 0) {
            if (field.nullable) continue;
            return .{ .refused = .unresolved_handle };
        }
        const real = resolver.resolve(field.kind, synthetic) orelse
            return .{ .refused = .unresolved_handle };
        std.mem.writeInt(u64, target[field.offset..][0..8], real, .little);
    }

    for (plan.arrays) |maybe_array| {
        const field = maybe_array orelse continue;
        const raw_count = std.mem.readInt(u32, target[field.count_offset..][0..4], .little);
        const pointer = std.mem.readInt(u64, target[field.pointer_offset..][0..8], .little);
        if (raw_count == 0 or pointer == 0) {
            // An empty array must still lose its guest pointer: a driver that
            // reads a count of zero may still be handed the pointer, and some
            // validation layers dereference it.
            @memset(target[field.pointer_offset..][0..8], 0);
            continue;
        }
        const bytes = if (field.count_is_bytes)
            @as(u64, raw_count)
        else
            @as(u64, raw_count) * field.element_size;
        const array_source = read(context, pointer, bytes) orelse
            return .{ .refused = .array_unreadable };
        const array_target = scratch.alloc(@intCast(bytes)) orelse
            return .{ .refused = .scratch_exhausted };
        @memcpy(array_target, array_source[0..@intCast(bytes)]);

        if (field.nested) |nested| {
            var index: usize = 0;
            while (index < raw_count) : (index += 1) {
                const element = index * field.element_size;
                const pointer_at = element + nested.pointer_offset;
                const nested_pointer = std.mem.readInt(u64, array_target[pointer_at..][0..8], .little);
                if (nested_pointer == 0) continue;
                const nested_count = std.mem.readInt(u32, array_target[element + nested.count_offset ..][0..4], .little);
                if (nested_count == 0) {
                    @memset(array_target[pointer_at..][0..8], 0);
                    continue;
                }
                const nested_bytes: u64 = @as(u64, nested_count) * @sizeOf(u64);
                const nested_source = read(context, nested_pointer, nested_bytes) orelse
                    return .{ .refused = .array_unreadable };
                const nested_target = scratch.alloc(@intCast(nested_bytes)) orelse
                    return .{ .refused = .scratch_exhausted };
                @memcpy(nested_target, nested_source[0..@intCast(nested_bytes)]);
                var handle_index: usize = 0;
                while (handle_index < nested_count) : (handle_index += 1) {
                    const at = handle_index * @sizeOf(u64);
                    const synthetic = std.mem.readInt(u64, nested_target[at..][0..8], .little);
                    if (synthetic == 0) continue;
                    const real = resolver.resolve(nested.kind, synthetic) orelse
                        return .{ .refused = .unresolved_handle };
                    std.mem.writeInt(u64, nested_target[at..][0..8], real, .little);
                }
                std.mem.writeInt(u64, array_target[pointer_at..][0..8], @intFromPtr(nested_target.ptr), .little);
            }
        }

        if (field.forbidden_pointer_offset) |offset| {
            var index: usize = 0;
            while (index < raw_count) : (index += 1) {
                const at = index * field.element_size + offset;
                if (std.mem.readInt(u64, array_target[at..][0..8], .little) != 0) {
                    return .{ .refused = .nested_pointer };
                }
            }
        }

        if (field.element_handle) |kind| {
            var index: usize = 0;
            while (index < raw_count) : (index += 1) {
                const at = index * field.element_size;
                const synthetic = std.mem.readInt(u64, array_target[at..][0..8], .little);
                if (synthetic == 0) continue;
                const real = resolver.resolve(kind, synthetic) orelse
                    return .{ .refused = .unresolved_handle };
                std.mem.writeInt(u64, array_target[at..][0..8], real, .little);
            }
        }

        std.mem.writeInt(u64, target[field.pointer_offset..][0..8], @intFromPtr(array_target.ptr), .little);
    }

    return .{ .ready = target };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const TestMemory = struct {
    base: u64,
    bytes: []u8,
    handles: std.AutoHashMap(u64, u64),

    fn read(context: *anyopaque, address: u64, length: u64) ?[]const u8 {
        const self: *TestMemory = @ptrCast(@alignCast(context));
        if (address < self.base) return null;
        const offset = address - self.base;
        if (offset + length > self.bytes.len) return null;
        return self.bytes[@intCast(offset)..][0..@intCast(length)];
    }

    fn lookup(context: *anyopaque, kind: HandleKind, synthetic: u64) ?u64 {
        _ = kind;
        const self: *TestMemory = @ptrCast(@alignCast(context));
        return self.handles.get(synthetic);
    }

    fn resolver(self: *TestMemory) Resolver {
        return .{ .context = self, .lookup = lookup };
    }
};

fn testMemory(allocator: std.mem.Allocator, base: u64, size: usize) !TestMemory {
    const bytes = try allocator.alloc(u8, size);
    @memset(bytes, 0);
    return .{ .base = base, .bytes = bytes, .handles = std.AutoHashMap(u64, u64).init(allocator) };
}

// The exact crash: a guest pointer handed to a driver that dereferences it as a
// host pointer, with no error path.
test "an array pointer is rewritten to host scratch rather than passed through" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 512);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    const plan = planFor("vkCreateDescriptorSetLayout").?;
    // The create-info at 0x1000, its bindings array at 0x1100.
    std.mem.writeInt(u32, memory.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "binding_count")..][0..4], 2, .little);
    std.mem.writeInt(u64, memory.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "bindings")..][0..8], 0x1100, .little);
    // Two bindings, no immutable samplers.
    std.mem.writeInt(u32, memory.bytes[0x100..][0..4], 7, .little);
    std.mem.writeInt(u32, memory.bytes[0x100 + @sizeOf(DescriptorSetLayoutBinding) ..][0..4], 9, .little);

    var scratch = Scratch{};
    const result = marshal(plan, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read);
    const ready = switch (result) {
        .ready => |bytes| bytes,
        .refused => return error.TestUnexpectedResult,
    };

    const rewritten = std.mem.readInt(u64, ready[@offsetOf(DescriptorSetLayoutCreateInfo, "bindings")..][0..8], .little);
    try std.testing.expect(rewritten != 0x1100);
    // And it points at the translated copy, with the contents intact.
    const bindings: [*]const DescriptorSetLayoutBinding = @ptrFromInt(rewritten);
    try std.testing.expectEqual(@as(u32, 7), bindings[0].binding);
    try std.testing.expectEqual(@as(u32, 9), bindings[1].binding);
}

// A synthetic handle is not a driver object, and is frequently shaped like a
// pointer — so passing one through is the same crash at a different address.
test "handles inside a structure and inside its arrays are translated" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 512);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();
    try memory.handles.put(0xfffff50000000151, 0xAAAA);
    try memory.handles.put(0xfffff50000000161, 0xBBBB);

    const plan = planFor("vkCreateFramebuffer").?;
    std.mem.writeInt(u64, memory.bytes[@offsetOf(FramebufferCreateInfo, "render_pass")..][0..8], 0xfffff50000000151, .little);
    std.mem.writeInt(u32, memory.bytes[@offsetOf(FramebufferCreateInfo, "attachment_count")..][0..4], 1, .little);
    std.mem.writeInt(u64, memory.bytes[@offsetOf(FramebufferCreateInfo, "attachments")..][0..8], 0x1100, .little);
    std.mem.writeInt(u64, memory.bytes[0x100..][0..8], 0xfffff50000000161, .little);

    var scratch = Scratch{};
    const ready = switch (marshal(plan, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => |bytes| bytes,
        .refused => return error.TestUnexpectedResult,
    };

    try std.testing.expectEqual(
        @as(u64, 0xAAAA),
        std.mem.readInt(u64, ready[@offsetOf(FramebufferCreateInfo, "render_pass")..][0..8], .little),
    );
    const attachments_ptr = std.mem.readInt(u64, ready[@offsetOf(FramebufferCreateInfo, "attachments")..][0..8], .little);
    const attachments: [*]const u64 = @ptrFromInt(attachments_ptr);
    try std.testing.expectEqual(@as(u64, 0xBBBB), attachments[0]);
}

// A handle with no real counterpart names an object that was never created on
// the device, so the call cannot mean what it says.
test "an unresolved handle refuses the structure rather than passing zero" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 512);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    const plan = planFor("vkCreateImageView").?;
    std.mem.writeInt(u64, memory.bytes[@offsetOf(ImageViewCreateInfo, "image")..][0..8], 0xfffff5000000dead, .little);

    var scratch = Scratch{};
    switch (marshal(plan, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => return error.TestUnexpectedResult,
        .refused => |refusal| try std.testing.expectEqual(Refusal.unresolved_handle, refusal),
    }
}

// Graphics pipelines still remain modelled until their much larger nested
// state graph has a plan. Render passes are handled by marshalRenderPass
// instead, because refusing them permanently would stop the first real render
// pass from ever reaching the driver.
test "an undescribed graphics pipeline remains modelled" {
    try std.testing.expect(planFor("vkCreateGraphicsPipelines") == null);
    try std.testing.expect(planFor("vkCreateRenderPass") == null);
    try std.testing.expect(planFor("vkCreateSampler") != null);
    try std.testing.expect(std.mem.indexOf(u8, Refusal.no_plan.meaning(), "modelled path is kept") != null);
}

test "nested render pass arrays are copied into host scratch" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 4096);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    const root = @as(*RenderPassCreateInfo, @ptrCast(@alignCast(memory.bytes.ptr)));
    root.* = .{
        .attachment_count = 1,
        .attachments = @ptrFromInt(0x1100),
        .subpass_count = 1,
        .subpasses = @ptrFromInt(0x1200),
        .dependency_count = 1,
        .dependencies = @ptrFromInt(0x1300),
    };
    const attachment = @as(*AttachmentDescription, @ptrCast(@alignCast(memory.bytes[0x100..].ptr)));
    attachment.format = 37;
    attachment.samples = 1;

    const subpass = @as(*SubpassDescription, @ptrCast(@alignCast(memory.bytes[0x200..].ptr)));
    subpass.* = .{
        .input_attachment_count = 1,
        .input_attachments = @ptrFromInt(0x1400),
        .color_attachment_count = 1,
        .color_attachments = @ptrFromInt(0x1410),
        .resolve_attachments = @ptrFromInt(0x1420),
        .depth_stencil_attachment = @ptrFromInt(0x1430),
        .preserve_attachment_count = 1,
        .preserve_attachments = @ptrFromInt(0x1440),
    };
    const input = @as(*AttachmentReference, @ptrCast(@alignCast(memory.bytes[0x400..].ptr)));
    input.* = .{ .attachment = 0, .layout = 5 };
    const color = @as(*AttachmentReference, @ptrCast(@alignCast(memory.bytes[0x410..].ptr)));
    color.* = .{ .attachment = 0, .layout = 6 };
    const resolve = @as(*AttachmentReference, @ptrCast(@alignCast(memory.bytes[0x420..].ptr)));
    resolve.* = .{ .attachment = 0, .layout = 7 };
    const depth = @as(*AttachmentReference, @ptrCast(@alignCast(memory.bytes[0x430..].ptr)));
    depth.* = .{ .attachment = 0, .layout = 8 };
    std.mem.writeInt(u32, memory.bytes[0x440..][0..4], 0, .little);
    const dependency = @as(*SubpassDependency, @ptrCast(@alignCast(memory.bytes[0x300..].ptr)));
    dependency.src_stage_mask = 1;
    dependency.dst_stage_mask = 2;

    var scratch = Scratch{};
    const ready = switch (marshalRenderPass(0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => |bytes| bytes,
        .refused => |refusal| {
            std.debug.print("unexpected render pass refusal: {s}\n", .{refusal.meaning()});
            return error.TestUnexpectedResult;
        },
    };
    const translated = @as(*RenderPassCreateInfo, @ptrCast(@alignCast(ready.ptr)));
    try std.testing.expect(@intFromPtr(translated.attachments.?) != 0x1100);
    try std.testing.expect(@intFromPtr(translated.subpasses.?) != 0x1200);
    try std.testing.expect(@intFromPtr(translated.dependencies.?) != 0x1300);
    const translated_subpass = @as([*]const SubpassDescription, @ptrCast(@alignCast(translated.subpasses.?)))[0];
    try std.testing.expectEqual(@as(u32, 6), @as([*]const AttachmentReference, @ptrCast(@alignCast(translated_subpass.color_attachments.?)))[0].layout);
    try std.testing.expectEqual(@as(u32, 8), @as(*const AttachmentReference, @ptrCast(@alignCast(translated_subpass.depth_stencil_attachment.?))).layout);
    try std.testing.expectEqual(@as(u32, 2), @as([*]const SubpassDependency, @ptrCast(@alignCast(translated.dependencies.?)))[0].dst_stage_mask);
}

// The presenter's first descriptor set layout binds an immutable sampler, so
// this path is the bring-up's first structure rather than an edge case.
test "an immutable sampler array is translated rather than refused" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 1024);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    try memory.handles.put(0xfffff5000000abcd, 0xCAFE);

    const plan = planFor("vkCreateDescriptorSetLayout").?;
    std.mem.writeInt(u32, memory.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "binding_count")..][0..4], 1, .little);
    std.mem.writeInt(u64, memory.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "bindings")..][0..8], 0x1100, .little);
    std.mem.writeInt(u32, memory.bytes[0x100 + @offsetOf(DescriptorSetLayoutBinding, "descriptor_count") ..][0..4], 1, .little);
    std.mem.writeInt(
        u64,
        memory.bytes[0x100 + @offsetOf(DescriptorSetLayoutBinding, "immutable_samplers") ..][0..8],
        0x1200,
        .little,
    );
    std.mem.writeInt(u64, memory.bytes[0x200..][0..8], 0xfffff5000000abcd, .little);

    var scratch = Scratch{};
    const ready = switch (marshal(plan, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => |bytes| bytes,
        .refused => return error.TestUnexpectedResult,
    };
    const bindings_ptr = std.mem.readInt(u64, ready[@offsetOf(DescriptorSetLayoutCreateInfo, "bindings")..][0..8], .little);
    const bindings: [*]const DescriptorSetLayoutBinding = @ptrFromInt(bindings_ptr);
    const samplers: [*]const u64 = @ptrCast(@alignCast(bindings[0].immutable_samplers.?));
    try std.testing.expectEqual(@as(u64, 0xCAFE), samplers[0]);
}

// A driver handed a count of zero may still be given the pointer, and some
// validation layers dereference it.
test "an empty array still loses its guest pointer" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 512);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    const plan = planFor("vkCreatePipelineLayout").?;
    std.mem.writeInt(u64, memory.bytes[@offsetOf(PipelineLayoutCreateInfo, "set_layouts")..][0..8], 0xdeadbeef, .little);
    std.mem.writeInt(u64, memory.bytes[@offsetOf(PipelineLayoutCreateInfo, "push_constant_ranges")..][0..8], 0xfeedface, .little);

    var scratch = Scratch{};
    const ready = switch (marshal(plan, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => |bytes| bytes,
        .refused => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(
        @as(u64, 0),
        std.mem.readInt(u64, ready[@offsetOf(PipelineLayoutCreateInfo, "set_layouts")..][0..8], .little),
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        std.mem.readInt(u64, ready[@offsetOf(PipelineLayoutCreateInfo, "push_constant_ranges")..][0..8], .little),
    );
}

test "pNext is always cleared, whatever the structure" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 512);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    std.mem.writeInt(u64, memory.bytes[8..][0..8], 0xCAFEBABE, .little);
    var scratch = Scratch{};
    const ready = switch (marshal(planFor("vkCreateSampler").?, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => |bytes| bytes,
        .refused => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ready[8..][0..8], .little));
}

test "an unreadable structure or array is refused rather than read out of bounds" {
    const allocator = std.testing.allocator;
    var memory = try testMemory(allocator, 0x1000, 64);
    defer allocator.free(memory.bytes);
    defer memory.handles.deinit();

    var scratch = Scratch{};
    // The sampler structure is larger than the mapping.
    switch (marshal(planFor("vkCreateSampler").?, 0x1000, &scratch, memory.resolver(), &memory, TestMemory.read)) {
        .ready => return error.TestUnexpectedResult,
        .refused => |refusal| try std.testing.expectEqual(Refusal.unreadable, refusal),
    }

    // A readable structure pointing at an unreadable array.
    var wide = try testMemory(allocator, 0x1000, 128);
    defer allocator.free(wide.bytes);
    defer wide.handles.deinit();
    std.mem.writeInt(u32, wide.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "binding_count")..][0..4], 64, .little);
    std.mem.writeInt(u64, wide.bytes[@offsetOf(DescriptorSetLayoutCreateInfo, "bindings")..][0..8], 0x9000, .little);
    scratch.reset();
    switch (marshal(planFor("vkCreateDescriptorSetLayout").?, 0x1000, &scratch, wide.resolver(), &wide, TestMemory.read)) {
        .ready => return error.TestUnexpectedResult,
        .refused => |refusal| try std.testing.expectEqual(Refusal.array_unreadable, refusal),
    }
}

// Forwarding a truncated array would be worse than not forwarding at all.
test "an exhausted scratch refuses instead of truncating" {
    var scratch = Scratch{};
    try std.testing.expect(scratch.alloc(scratch_bytes + 1) == null);
    try std.testing.expect(scratch.alloc(64) != null);
    scratch.reset();
    try std.testing.expectEqual(@as(usize, 0), scratch.used);
}

// Offsets come from the compiler. A hand-counted one that is wrong by four
// bytes makes a driver read a length out of a flags field.
test "structure layouts match the Vulkan ABI" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(DescriptorSetLayoutCreateInfo));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(DescriptorSetLayoutCreateInfo, "bindings"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(DescriptorSetLayoutBinding));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(PipelineLayoutCreateInfo));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(PipelineLayoutCreateInfo, "set_layouts"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(PipelineLayoutCreateInfo, "push_constant_ranges"));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(DescriptorPoolCreateInfo));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(ImageViewCreateInfo));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(ImageViewCreateInfo, "image"));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(FramebufferCreateInfo));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(FramebufferCreateInfo, "attachments"));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(ShaderModuleCreateInfo));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(SamplerCreateInfo));
    try std.testing.expectEqual(@as(usize, 88), @sizeOf(ImageCreateInfo));
    try std.testing.expectEqual(@as(usize, 72), @offsetOf(ImageCreateInfo, "queue_family_indices"));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(BufferCreateInfo));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(BufferCreateInfo, "queue_family_indices"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(FlagsOnlyCreateInfo));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(BufferViewCreateInfo, "buffer"));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(RenderPassCreateInfo));
    try std.testing.expectEqual(@as(usize, 36), @sizeOf(AttachmentDescription));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(AttachmentReference));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(SubpassDescription));
    try std.testing.expectEqual(@as(usize, 28), @sizeOf(SubpassDependency));

    inline for (.{
        HandleKind.descriptor_set_layout, HandleKind.render_pass, HandleKind.image,
        HandleKind.image_view,            HandleKind.sampler,     HandleKind.buffer,
        HandleKind.pipeline_layout,
    }) |kind| try std.testing.expect(kind.label().len > 0);
    inline for (.{
        Refusal.no_plan,
        Refusal.unreadable,
        Refusal.array_unreadable,
        Refusal.scratch_exhausted,
        Refusal.unresolved_handle,
        Refusal.nested_pointer,
    }) |refusal| {
        try std.testing.expect(refusal.label().len > 0);
        try std.testing.expect(refusal.meaning().len > 40);
    }
}
