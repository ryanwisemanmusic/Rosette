// Split implementation for Forwarder; wrappers keep the public state API stable.
const process = @import("../dynamic_library_forwarder.zig");
const __ForwarderInternals = process.__ForwarderInternals;
const Forwarder = process.Forwarder;
const HandleMap = __ForwarderInternals._HandleMap;
const MAX_SWAPCHAIN_IMAGES = __ForwarderInternals._MAX_SWAPCHAIN_IMAGES;
const NativeSurfaceResult = __ForwarderInternals._NativeSurfaceResult;
const VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT = __ForwarderInternals._VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
const VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = __ForwarderInternals._VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
const VK_SWAPCHAIN_CREATE_INFO_SIZE = __ForwarderInternals._VK_SWAPCHAIN_CREATE_INFO_SIZE;
const VK_SYNTHETIC_DEVICE = __ForwarderInternals._VK_SYNTHETIC_DEVICE;
const VK_SYNTHETIC_SURFACE = __ForwarderInternals._VK_SYNTHETIC_SURFACE;
const VulkanResource = __ForwarderInternals._VulkanResource;
const abi = __ForwarderInternals._abi;
const createHandle = __ForwarderInternals._createHandle;
const dlerror = __ForwarderInternals._dlerror;
const dlsym = __ForwarderInternals._dlsym;
const guest_context = __ForwarderInternals._guest_context;
const lastDlError = __ForwarderInternals._lastDlError;
const machoCapturePrint = __ForwarderInternals._machoCapturePrint;
const presentDiagnosticMetalFrame = __ForwarderInternals._presentDiagnosticMetalFrame;
const rangeContains = __ForwarderInternals._rangeContains;
const registerOpaqueHandle = __ForwarderInternals._registerOpaqueHandle;
const rosette_gpu = __ForwarderInternals._rosette_gpu;
const std = __ForwarderInternals._std;
const transport_timing = __ForwarderInternals._transport_timing;
const vkErrorInitializationFailed = __ForwarderInternals._vkErrorInitializationFailed;
const vkErrorInitializationFailedSigned = __ForwarderInternals._vkErrorInitializationFailedSigned;
const vkErrorOutOfHostMemory = __ForwarderInternals._vkErrorOutOfHostMemory;
const vulkanLoaderCandidates = __ForwarderInternals._vulkanLoaderCandidates;
const bringUpNativePresenter = Forwarder.bringUpNativePresenter;
const copyGuestStructs = Forwarder.copyGuestStructs;
const copyGuestValue = Forwarder.copyGuestValue;
const createNativeMetalSurface = Forwarder.createNativeMetalSurface;
const currentHostDrawableExtent = Forwarder.currentHostDrawableExtent;
const ensureRealDevice = Forwarder.ensureRealDevice;
const findVulkanMemoryRecord = Forwarder.findVulkanMemoryRecord;
const forward = Forwarder.forward;
const fsiSubmitExpanded = Forwarder.fsiSubmitExpanded;
const fsiSubmitNeedsExpansion = Forwarder.fsiSubmitNeedsExpansion;
const libraryHandle = Forwarder.libraryHandle;
const lockVulkanQueueApi = Forwarder.lockVulkanQueueApi;
const mapVulkanHandle = Forwarder.mapVulkanHandle;
const nextVulkanObject = Forwarder.nextVulkanObject;
const noteFsiSubmittedCommandBuffer = Forwarder.noteFsiSubmittedCommandBuffer;
const noteGraphicsExtentContractFailure = Forwarder.noteGraphicsExtentContractFailure;
const noteNativeVulkanLoaderResolved = Forwarder.noteNativeVulkanLoaderResolved;
const noteRealVulkanResult = Forwarder.noteRealVulkanResult;
const noteSubmittedCommandTargets = Forwarder.noteSubmittedCommandTargets;
const noteVulkanMapCapacityRefusal = Forwarder.noteVulkanMapCapacityRefusal;
const publishGuestFrontBuffer = Forwarder.publishGuestFrontBuffer;
const realDeviceLostResult = Forwarder.realDeviceLostResult;
const refuseVulkanCall = Forwarder.refuseVulkanCall;
const releaseVulkanHandle = Forwarder.releaseVulkanHandle;
const resolveNativeVulkanSymbol = Forwarder.resolveNativeVulkanSymbol;
const trackedImageCount = Forwarder.trackedImageCount;
const uploadMappedMemoryBeforeSubmit = Forwarder.uploadMappedMemoryBeforeSubmit;

pub fn prepareMetalDrawableForSwapchain(self: anytype, state: anytype, width: u32, height: u32) bool {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "prepareNativeMetalDrawable")) return true;

    self.metal_drawable_prepare_attempts +|= 1;
    if (width == 0 or height == 0) {
        self.metal_drawable_prepare_failures +|= 1;
        machoCapturePrint(
            "macho-processor: CAMetalLayer drawable preflight failed: invalid swapchain extent={d}x{d}\n",
            .{ width, height },
        );
        self.noteGraphicsExtentContractFailure(
            state,
            width,
            height,
            0,
            0,
            "invalid_swapchain_extent",
        );
        return false;
    }
    if (!state.prepareNativeMetalDrawable(width, height)) {
        self.metal_drawable_prepare_failures +|= 1;
        machoCapturePrint(
            "macho-processor: CAMetalLayer drawable preflight failed: requested={d}x{d} attempts={d} failures={d}; refusing to create a real swapchain with an unproven drawable extent\n",
            .{ width, height, self.metal_drawable_prepare_attempts, self.metal_drawable_prepare_failures },
        );
        const observed = currentHostDrawableExtent();
        self.noteGraphicsExtentContractFailure(
            state,
            width,
            height,
            observed.width,
            observed.height,
            "CAMetalLayer_preflight_refused",
        );
        return false;
    }
    self.metal_drawable_prepare_successes +|= 1;
    self.metal_drawable_prepared_width = width;
    self.metal_drawable_prepared_height = height;
    machoCapturePrint(
        "macho-processor: CAMetalLayer drawable preflight ready: extent={d}x{d} attempts={d} successes={d}; Vulkan capability negotiation and swapchain creation now use this extent\n",
        .{ width, height, self.metal_drawable_prepare_attempts, self.metal_drawable_prepare_successes },
    );
    return true;
}

pub fn yieldMetalDrawableToSwapchain(self: anytype, state: anytype, width: u32, height: u32) void {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "setNativeMetalDrawableOwner")) return;
    const ownership_changed = state.setNativeMetalDrawableOwner(true);
    if (!ownership_changed) {
        // The native presenter may already have handed this layer to
        // MoltenVK.  A same-size preflight proves that this swapchain is
        // using that existing owner; treating the unchanged flag as a
        // failed handoff would make the present ledger report the layer
        // as bridge-owned even though the driver is vending drawables.
        if (self.metal_drawable_prepare_successes == 0 or
            self.metal_drawable_prepared_width != width or
            self.metal_drawable_prepared_height != height) return;
        self.metal_drawable_yielded = true;
        self.drawable_owner = .guest_swapchain;
        machoCapturePrint(
            "macho-processor: CAMetalLayer drawableSize already owned by the Vulkan driver: swapchain extent={d}x{d}; preflight verified the existing owner and the window bridge remains hands-off\n",
            .{ width, height },
        );
        return;
    }
    self.metal_drawable_yielded = true;
    self.drawable_owner = .guest_swapchain;
    machoCapturePrint(
        "macho-processor: CAMetalLayer drawableSize handed to the Vulkan driver: swapchain extent={d}x{d}. The window bridge stops resizing the drawable from here; MoltenVK owns it while a swapchain is live, and a write it did not make reads to it as the swapchain going out of date\n",
        .{ width, height },
    );
}

pub fn retireNativePresenterForGuestSwapchain(self: anytype, guest_width: u32, guest_height: u32) void {
    const presenter = &self.native_presenter;
    if (!presenter.stage.isReady()) return;
    const layer = presenter.metal_layer;
    if (layer == 0) return;
    // Only when they are contending for the same layer. A presenter bound
    // to some other surface is not in the guest's way.
    const guest_layer = self.present_chain.layerOfSwapchainOwnedBy(.guest);
    if (guest_layer == 0 or guest_layer != layer) return;

    const retired_swapchain: u64 = presenter.swapchain;
    const retired_surface: u64 = presenter.surface;
    const retired_width = presenter.extent.width;
    const retired_height = presenter.extent.height;
    presenter.shutdown();
    if (retired_swapchain != 0) self.present_chain.retireSwapchain(retired_swapchain);
    if (retired_surface != 0) self.present_chain.retireSurface(retired_surface);
    self.native_presenter_stage_logged = presenter.stage;
    self.native_presenter_retired_for_guest +|= 1;
    machoCapturePrint(
        "macho-processor: native Vulkan presenter stood down: the guest built its own {d}x{d} swapchain on CAMetalLayer 0x{x}, which Rosette's {d}x{d} swapchain was also bound to. One layer vends one drawable pool, so the two were taking turns; Rosette yields it because the guest is the one with a picture to show\n",
        .{ guest_width, guest_height, layer, retired_width, retired_height },
    );
}

pub fn registerNativePresenterInPresentChain(self: anytype, _state: anytype) void {
    _ = _state;
    // The caller claims the drawable immediately after the presenter has
    // created its swapchain. Do not call the guest handoff helper here:
    // doing so would relabel a native-presenter lease as a guest lease and
    // would make the next guest preflight look like an unexplained owner
    // transition. The lease remains native until the guest swapchain is
    // created and `retireNativePresenterForGuestSwapchain` closes it.
    const presenter = &self.native_presenter;
    if (presenter.metal_layer == 0) return;
    const surface: u64 = presenter.surface;
    const swapchain: u64 = presenter.swapchain;
    if (surface == 0 or swapchain == 0) return;
    self.present_chain.noteSurface(surface, presenter.metal_layer, .rosette);
    self.present_chain.noteSwapchain(.{
        .handle = swapchain,
        .surface = surface,
        .layer = presenter.metal_layer,
        .owner = .rosette,
        .width = presenter.extent.width,
        .height = presenter.extent.height,
        .format = presenter.surface_format.format,
        .present_mode = presenter.present_mode,
        .image_count = presenter.swapchain_image_count,
        .image_usage = presenter.image_usage,
        .requested_image_usage = presenter.image_usage,
    });
}

pub fn preflightNativePresenter(self: anytype, state: anytype) rosette_gpu.NativePresenterStage {
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "nativeMetalLayerHostPointer")) return .unstarted;

    const layer = state.nativeMetalLayerHostPointer();
    if (layer == 0) return .unstarted;
    const width = if (@hasDecl(State, "nativeWindowWidth")) state.nativeWindowWidth() else 1280;
    const height = if (@hasDecl(State, "nativeWindowHeight")) state.nativeWindowHeight() else 720;
    const requested_width = @max(width, 1);
    const requested_height = @max(height, 1);
    if (self.native_presenter.stage.isReady()) {
        // The preflight is also the recurring admission check. Do not let
        // a previous success survive a later AppKit/backing-store extent
        // change just because the native presenter still says ready.
        if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
            return .ready;
        }
        const report = &self.native_presenter.report;
        if (!rosette_gpu.vulkan.selection.extentMatches(
            .{ .width = report.extent_width, .height = report.extent_height },
            .{ .width = requested_width, .height = requested_height },
        )) {
            self.noteGraphicsExtentContractFailure(
                state,
                requested_width,
                requested_height,
                report.extent_width,
                report.extent_height,
                "native_presenter_preflight_ready_extent_changed",
            );
        }
        return .ready;
    }
    if (self.native_presenter.stage == .device_lost) return .device_lost;

    var candidates = vulkanLoaderCandidates("libvulkan.1.dylib");
    var library: ?*anyopaque = null;
    var selected_path: []const u8 = "none";
    for (candidates.paths[0..candidates.count]) |candidate| {
        self.native_vulkan_loader_attempts +|= 1;
        machoCapturePrint(
            "macho-processor: native Vulkan preflight loader begin: attempt={d} path={s}\n",
            .{ self.native_vulkan_loader_attempts, candidate },
        );
        const handle = self.libraryHandle(candidate) orelse {
            self.native_vulkan_loader_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native Vulkan preflight loader unavailable: attempt={d} path={s} dlerror={s}\n",
                .{ self.native_vulkan_loader_attempts, candidate, lastDlError() },
            );
            continue;
        };
        if (dlsym(handle, "vkGetInstanceProcAddr") == null) {
            self.native_vulkan_loader_failures +|= 1;
            machoCapturePrint(
                "macho-processor: native Vulkan preflight loader missing vkGetInstanceProcAddr: attempt={d} path={s} dlerror={s}\n",
                .{ self.native_vulkan_loader_attempts, candidate, lastDlError() },
            );
            continue;
        }
        library = handle;
        selected_path = candidate;
        self.noteNativeVulkanLoaderResolved(candidate);
        machoCapturePrint(
            "macho-processor: native Vulkan preflight loader ready: attempt={d} path={s} host_handle=0x{x}\n",
            .{ self.native_vulkan_loader_attempts, candidate, @intFromPtr(handle) },
        );
        break;
    }

    // Keep the hidden admission smoke test under the same geometry
    // contract as the guest path. Otherwise the smoke presenter can
    // establish a 2x drawable owner before the guest ever asks for its
    // real 1280x720 swapchain.
    if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
        machoCapturePrint(
            "macho-processor: native Vulkan preflight deferred: CAMetalLayer drawable extent is not proven at the default {d}x{d}; no smoke-test swapchain was created\n",
            .{ requested_width, requested_height },
        );
        return self.native_presenter.stage;
    }
    self.native_presenter_attempts +|= 1;
    const stage = self.native_presenter.bringUp(
        .{
            .context = if (library) |handle| handle else null,
            .lookup = resolveNativeVulkanSymbol,
        },
        layer,
        requested_width,
        requested_height,
    );
    self.native_presenter_stage_logged = stage;
    machoCapturePrint(
        "macho-processor: native Vulkan presenter preflight: attempt={d} stage={s} ({s}) loader={s} VkResult={d} rejection={s} adapter={s} physical_devices={d} queue={d}/{d} swapchain_images={d} extent={d}x{d} requested={d}x{d} native_present_completed=NO\n",
        .{
            self.native_presenter_attempts,
            @tagName(stage),
            stage.label(),
            selected_path,
            self.native_presenter.report.last_result,
            self.native_presenter.report.rejectionLabel(),
            if (self.native_presenter.report.adapter_name_length != 0)
                self.native_presenter.report.adapterName()
            else
                "unselected",
            self.native_presenter.report.physical_device_count,
            self.native_presenter.report.graphics_family,
            self.native_presenter.report.present_family,
            self.native_presenter.report.swapchain_image_count,
            self.native_presenter.report.extent_width,
            self.native_presenter.report.extent_height,
            self.native_presenter.report.requested_extent_width,
            self.native_presenter.report.requested_extent_height,
        },
    );
    if (self.native_presenter.extentContractFailed()) {
        const report = &self.native_presenter.report;
        self.noteGraphicsExtentContractFailure(
            state,
            requested_width,
            requested_height,
            report.extent_width,
            report.extent_height,
            "native_presenter_preflight_surface_capability_extent_mismatch",
        );
    }
    if (stage.isReady()) {
        self.vulkan_presenter_stage = .native_drawable_ready;
        if (@hasDecl(State, "setNativeMetalDrawableOwner")) {
            _ = state.setNativeMetalDrawableOwner(true);
            self.drawable_owner = .native_presenter;
            machoCapturePrint(
                "macho-processor: CAMetalLayer drawable owner: native_presenter extent={d}x{d}; the admission smoke swapchain is protected from AppKit/layout writes until the guest handoff retires it\n",
                .{ requested_width, requested_height },
            );
        }
        // Confirm the actual owner state after the driver's swapchain
        // creation, not only the pre-create layer write and capabilities.
        // MoltenVK must not be allowed to turn a successful 720p admission
        // into a Retina-sized drawable silently.
        if (!self.prepareMetalDrawableForSwapchain(state, requested_width, requested_height)) {
            return stage;
        }
        self.negotiateRosetteGpuBoundary("native_presenter_preflight_ready");
    }
    return stage;
}

pub fn discoverGuestFrameSource(self: anytype, state: anytype) void {
    self.frame_source_scans +|= 1;
    // The console's own framebuffer outranks any Vulkan image the emulator
    // described. When the emulator's GPU work does not execute, its images
    // stay exactly as empty as they were mapped, and this is the only
    // buffer that can hold a picture at all.
    if (self.publishGuestFrontBuffer(state)) return;
    var best: ?*VulkanResource = null;
    var best_pixels: u64 = 0;
    var saw_image = false;
    var saw_bound = false;
    var saw_mapped = false;
    var saw_format = false;
    for (&self.vulkan_resources) |*record| {
        if (record.handle == 0 or record.kind != .image) continue;
        saw_image = true;
        if (record.width == 0 or record.height == 0) continue;
        if (rosette_gpu.vulkan.selection.bytesPerPixel(record.format) == null) continue;
        saw_format = true;
        if (record.memory == 0) continue;
        saw_bound = true;
        const allocation = self.findVulkanMemoryRecord(record.memory) orelse continue;
        if (allocation.mapped_base == 0) continue;
        saw_mapped = true;
        const pixels = @as(u64, record.width) * record.height;
        if (pixels <= best_pixels) continue;
        best_pixels = pixels;
        best = record;
    }
    const chosen = best orelse {
        // Each of these is a different missing link, and "no source" alone
        // would send a reader nowhere.
        self.frame_inbox.noteUnusable(if (!saw_image)
            .never_published
        else if (!saw_format)
            .format_unsupported
        else if (!saw_bound or !saw_mapped)
            .source_unmapped
        else
            .never_published);
        return;
    };
    const allocation = self.findVulkanMemoryRecord(chosen.memory) orelse return;
    const required = chosen.size_bytes;
    // `mapped_base` is a Rosette shadow allocation, while
    // `host_mapped_ptr` (when present) describes the exact native range
    // that the driver accepted. A resource record can only be used for
    // frame discovery when both coordinate systems contain the image.
    // Otherwise a stale or malformed synthetic offset would make the
    // bridge read unrelated guest memory and call it a frame.
    const mapped_length = if (allocation.host_mapped_ptr != null)
        allocation.host_mapped_size
    else
        allocation.mapped_size;
    if (!rangeContains(0, allocation.mapped_size, chosen.memory_offset, required) or
        mapped_length == 0 or
        !rangeContains(allocation.mapped_offset, mapped_length, chosen.memory_offset, required))
    {
        self.frame_inbox.noteUnusable(.source_truncated);
        return;
    }
    const address = std.math.add(u64, allocation.mapped_base, chosen.memory_offset) catch {
        self.frame_inbox.noteUnusable(.source_truncated);
        return;
    };
    const readable = state.guestMemoryConst(address, required);
    if (readable == null) {
        self.frame_inbox.noteUnusable(.source_truncated);
        return;
    }
    // An allocated, mapped, never-written image is zero throughout.
    // Presenting it would put a black frame on the window and label it
    // guest output, which is worse than showing nothing. The digest also
    // prevents a retained image from becoming a new frame on every scan.
    const content = rosette_gpu.frame_source.inspectContent(readable.?);
    if (!content.nonzero) {
        self.frame_inbox.noteUnusable(.never_published);
        return;
    }
    const publication = self.frame_inbox.publishIfChanged(.{
        .source_address = address,
        .source_length = required,
        .width = chosen.width,
        .height = chosen.height,
        .format = chosen.format,
        .row_pitch_bytes = chosen.row_pitch_bytes,
        .orientation = .top_down,
        .fit = .letterbox,
        .producer = .xenia_host,
        // Only the bootstrap's own swap observation may set this, and it is
        // supplied by the caller rather than inferred from a frame arriving.
        .guest_swap_observed = false,
    }, chosen.handle, content.digest);
    if (publication.disposition != .published) return;
    const serial = publication.serial;
    self.frame_source_discoveries +|= 1;
    if (self.frame_source_discoveries == 1) {
        machoCapturePrint(
            "macho-processor: GUEST FRAME SOURCE FOUND: image=0x{x} extent={d}x{d} format={d} pitch={d} bytes={d} guest_address=0x{x} serial={d}; a written, mapped, presentable guest image now feeds the native presenter\n",
            .{ chosen.handle, chosen.width, chosen.height, chosen.format, chosen.row_pitch_bytes, required, address, serial },
        );
    }
}

pub fn presentWindowFrame(self: anytype, state: anytype, serial: u64, width: u32, height: u32, stage_hint: u32) bool {
    if (self.native_presenter.stage.isReady()) {
        self.discoverGuestFrameSource(state);
        if (self.frame_inbox.acquire()) |descriptor| {
            const pixels = state.guestMemoryConst(descriptor.source_address, descriptor.source_length);
            if (pixels) |bytes| {
                const report = self.native_presenter.present(.{ .cpu_image = .{
                    .pixels = bytes,
                    .width = descriptor.width,
                    .height = descriptor.height,
                    .format = self.native_presenter.surface_format.format,
                    .row_pitch_bytes = descriptor.row_pitch_bytes,
                    .orientation = descriptor.orientation,
                    .fit = descriptor.fit,
                    .producer = descriptor.producer,
                    .guest_swap_observed = descriptor.guest_swap_observed,
                } });
                self.observeNativePresenterReport(report);
                self.frame_inbox.release(report.presented and report.source_copied);
                if (report.presented and report.source_copied) {
                    const frames = self.native_presenter.ledger.host_frames_presented +
                        self.native_presenter.ledger.guest_output_frames_presented;
                    if (frames <= 8 or frames % 120 == 0) {
                        machoCapturePrint(
                            "macho-processor: guest-sourced frame presented: serial={d} extent={d}x{d} composite={s} destination={d},{d} {d}x{d} class={s} guest_swap_observed={s}\n",
                            .{
                                descriptor.serial,
                                descriptor.width,
                                descriptor.height,
                                @tagName(report.composite),
                                report.destination.x,
                                report.destination.y,
                                report.destination.width,
                                report.destination.height,
                                report.classification.label(),
                                if (descriptor.guest_swap_observed) "YES" else "NO",
                            },
                        );
                    }
                    return true;
                }
                // The presenter could not use it. Say so rather than
                // falling through silently to a clear that looks the same.
                machoCapturePrint(
                    "macho-processor: guest-sourced frame rejected by the presenter: serial={d} extent={d}x{d} swapchain={d}x{d} source_format={d} swapchain_format={d} composite={s}; falling back to a diagnostic clear\n",
                    .{
                        descriptor.serial,
                        descriptor.width,
                        descriptor.height,
                        self.native_presenter.extent.width,
                        self.native_presenter.extent.height,
                        descriptor.format,
                        self.native_presenter.surface_format.format,
                        @tagName(report.composite),
                    },
                );
            } else {
                self.frame_inbox.release(false);
                self.frame_inbox.noteUnusable(.source_unmapped);
            }
        } else if (self.frame_source_absence_logged != self.frame_inbox.absence()) {
            self.frame_source_absence_logged = self.frame_inbox.absence();
            machoCapturePrint(
                "macho-processor: no guest frame source: {s} (scans={d} discoveries={d} images_tracked={d} image_bindings={d})\n",
                .{
                    self.frame_inbox.absence().label(),
                    self.frame_source_scans,
                    self.frame_source_discoveries,
                    self.trackedImageCount(),
                    self.vulkan_image_bindings,
                },
            );
        }
        // Cycled so a stalled presenter is visibly distinguishable from a
        // running one that has nothing new to show.
        const phase: f32 = @as(f32, @floatFromInt(serial % 120)) / 120.0;
        const report = self.native_presenter.present(.{
            .clear = .{ 0.05, 0.08 + phase * 0.3, 0.16 + (1.0 - phase) * 0.4, 1.0 },
        });
        self.observeNativePresenterReport(report);
        const frames = self.native_presenter.ledger.diagnostic_frames_presented;
        if (frames <= 8 or frames % 120 == 0 or !report.presented) {
            machoCapturePrint(
                "macho-processor: native Vulkan frame: serial={d} attempted={} generation={d} slot={d} image={d} acquire={d}({s}) submit={d} present={d}({s}) request_accepted={} gpu_completed={} completion={d} health={s} provenance={s} source=host_clear native_swapchain=YES native_queue_submit={s} guest_output=NO\n",
                .{
                    serial,
                    report.attempted,
                    report.generation,
                    report.frame_slot,
                    report.image_index,
                    report.acquire_result,
                    @tagName(report.acquire_outcome),
                    report.submit_result,
                    report.present_result,
                    @tagName(report.present_outcome),
                    report.present_request_accepted,
                    report.hardware_completed,
                    report.hardware_completion_result,
                    @tagName(report.health),
                    report.classification.label(),
                    if (report.submitted) "YES" else "NO",
                },
            );
        }
        return report.presented;
    }
    const presented = presentDiagnosticMetalFrame(state, serial, width, height, stage_hint);
    _ = self.frame_provenance.record(.{
        .producer = .diagnostic,
        .source_ready = true,
        // A Metal clear reaches the drawable without any of these.
        .native_command_recording = false,
        .native_submission = false,
        .native_presentation = false,
        .present_accepted = presented,
    });
    return presented;
}

pub fn observeNativePresenterReport(self: anytype, report: anytype) void {
    self.gpu_runtime.observeBackendProgress(report.submitted, report.presented);
    const live_boundary = self.native_presenter.boundary();
    const advertised = self.gpu_runtime.adapter.description.provided;
    if (live_boundary.presentation_native and !advertised.contains(.presentation)) {
        self.negotiateRosetteGpuBoundary("native_presentation_observed");
    }
}

pub fn realVulkanHasMemoryProperty(self: anytype, property: u32) bool {
    const count = @min(
        self.real_vulkan.physical_device_memory.memory_type_count,
        @as(u32, @intCast(abi.MAX_MEMORY_TYPES)),
    );
    for (0..@as(usize, @intCast(count))) |index| {
        if (self.real_vulkan.physical_device_memory.memory_types[index].property_flags & property != 0) return true;
    }
    return false;
}

pub fn realVulkanAdapterName(self: anytype) []const u8 {
    if (self.real_vulkan.physical_device == null) return "Vulkan guest device (not selected)";
    const identity: *const abi.PhysicalDeviceIdentity = @ptrCast(@alignCast(&self.real_vulkan.physical_device_properties));
    const name = identity.name();
    return if (name.len != 0) name else "Vulkan guest device (unnamed)";
}

pub fn guestVulkanBoundary(self: anytype) rosette_gpu.backend.VulkanBoundary {
    const state = &self.real_vulkan;
    const functions = &state.fn_ptrs;
    return .{
        .instance_native = state.instance != null,
        .surface_native = state.surface != 0,
        .physical_adapter_native = state.physical_device != null,
        .logical_device_native = state.deviceUsable(),
        .graphics_queue_native = state.graphics_queue != null,
        .compute_queue_native = state.compute_queue != null,
        .transfer_queue_native = state.transfer_queue != null,
        .host_visible_memory_native = self.realVulkanHasMemoryProperty(abi.MEMORY_PROPERTY_HOST_VISIBLE_BIT),
        .device_local_memory_native = self.realVulkanHasMemoryProperty(abi.MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        .guest_mapping_native = functions.allocate_memory != null and
            functions.free_memory != null and
            functions.map_memory != null and
            functions.unmap_memory != null,
        .buffer_native = functions.create_buffer != null and
            functions.destroy_buffer != null and
            functions.get_buffer_memory_requirements != null and
            functions.bind_buffer_memory != null,
        .image_native = functions.create_image != null and
            functions.destroy_image != null and
            functions.get_image_memory_requirements != null and
            functions.bind_image_memory != null,
        .sampler_native = functions.create_sampler != null and functions.destroy_sampler != null,
        .shader_native = functions.create_shader_module != null and
            functions.destroy_shader_module != null and
            functions.create_graphics_pipelines != null and
            functions.create_compute_pipelines != null,
        .command_buffer_native = functions.create_command_pool != null and
            functions.destroy_command_pool != null and
            functions.allocate_command_buffers != null and
            functions.free_command_buffers != null and
            functions.begin_command_buffer != null and
            functions.end_command_buffer != null,
        .barriers_native = functions.cmd_pipeline_barrier != null or functions.cmd_pipeline_barrier2 != null,
        .synchronization_native = functions.create_fence != null and
            functions.destroy_fence != null and
            functions.wait_for_fences != null and
            functions.create_semaphore != null and
            functions.destroy_semaphore != null,
        .swapchain_native = functions.create_swapchain != null and
            functions.destroy_swapchain != null and
            functions.get_swapchain_images != null,
        .presentation_native = functions.queue_present != null,
        .adapter_name = self.realVulkanAdapterName(),
        .buffer_alignment = 256,
        .image_alignment = 256,
        .guest_mapping_alignment = 4096,
        .adapter_token = if (state.physical_device) |device| @intFromPtr(device) else 0,
        .device_token = if (state.device) |device| @intFromPtr(device) else 0,
        .graphics_queue_token = if (state.graphics_queue) |queue| @intFromPtr(queue) else 0,
        .compute_queue_token = if (state.compute_queue) |queue| @intFromPtr(queue) else 0,
        .transfer_queue_token = if (state.transfer_queue) |queue| @intFromPtr(queue) else 0,
    };
}

pub fn logPendingGpuHandshake(self: anytype, reason: []const u8) void {
    self.gpu_handshake_probes +|= 1;
    machoCapturePrint(
        "macho-processor: Rosette GPU handshake probe #{d}: reason={s} status=pending authority=guest_device_creation; loader/shadow-instance facts are discovery only and no degraded execution session is admitted until a real guest VkDevice and graphics queue exist\n",
        .{ self.gpu_handshake_probes, reason },
    );
}

pub fn faultOnGpuHandshake(
    self: anytype,
    response: *const rosette_gpu.HandshakeResponse,
    reason: []const u8,
) noreturn {
    if (!self.gpu_handshake_faulted) {
        self.gpu_handshake_faulted = true;
        machoCapturePrint(
            "macho-processor: Rosette GPU handshake FAULT: reason={s} status={s} first_missing={s} missing_required=0x{x}:0x{x} negotiated=0x{x}:0x{x} detail={s}; native Vulkan execution is not permitted to continue\n",
            .{
                reason,
                @tagName(response.statusValue()),
                if (response.first_missing_capability == rosette_gpu.api.no_capability)
                    "none"
                else
                    rosette_gpu.api.capabilityName(@enumFromInt(response.first_missing_capability)),
                response.missing_required.high,
                response.missing_required.low,
                response.negotiated.high,
                response.negotiated.low,
                response.reasonSlice(),
            },
        );
    }
    _ = std.c.raise(std.c.SIG.SEGV);
    std.c.abort();
}

pub fn faultOnUnavailableVulkanCommand(self: anytype, name: []const u8) noreturn {
    _ = self;
    machoCapturePrint(
        "macho-processor: Vulkan command FAULT: {s} was reached through a previously published guest proc token, but no enabled native entry point exists; refusing a silent no-op\n",
        .{name},
    );
    _ = std.c.raise(std.c.SIG.SEGV);
    std.c.abort();
}

pub fn negotiateRosetteGpuBoundary(self: anytype, reason: []const u8) void {
    // A loader-open or shadow-instance callback is only a probe. It must
    // not create a degraded execution session from a boundary that has no
    // physical adapter/device/queue yet. The guest's real device is the
    // authoritative execution boundary when it exists; before that, the
    // native presenter is the only complete host-owned alternative.
    const guest_device_authoritative = self.real_vulkan.hasDevice();
    if (guest_device_authoritative) {
        self.gpu_runtime.installVulkanBoundary(self.guestVulkanBoundary());
        self.forwarding_contract = .{};
    } else if (self.native_presenter.stage != .unstarted) {
        self.gpu_runtime.installVulkanBoundary(self.native_presenter.boundary());
        self.forwarding_contract = .{};
        self.native_presenter.declareInto(&self.forwarding_contract);
    } else {
        self.logPendingGpuHandshake(reason);
        return;
    }
    const request = if (guest_device_authoritative)
        rosette_gpu.HandshakeRequest.xeniaDeviceExecution()
    else
        rosette_gpu.HandshakeRequest.xeniaObservation();
    self.gpu_handshake_response = self.gpu_runtime.negotiate(request);
    self.gpu_handshake_updates +|= 1;
    const response = &self.gpu_handshake_response;
    machoCapturePrint(
        "macho-processor: Rosette GPU handshake #{d}: reason={s} api={d} backend={s} status={s} session=0x{x} negotiated=0x{x}:0x{x} missing_required=0x{x}:0x{x} missing_desired=0x{x}:0x{x} first_missing={s} detail={s}\n",
        .{
            self.gpu_handshake_updates,
            reason,
            response.version,
            @tagName(response.backendValue()),
            @tagName(response.statusValue()),
            response.session,
            response.negotiated.high,
            response.negotiated.low,
            response.missing_required.high,
            response.missing_required.low,
            response.missing_desired.high,
            response.missing_desired.low,
            if (response.first_missing_capability == rosette_gpu.api.no_capability)
                "none"
            else
                rosette_gpu.api.capabilityName(@enumFromInt(response.first_missing_capability)),
            response.reasonSlice(),
        },
    );
    // Say whether a degraded status is a defect or the design.
    //
    // `presentation` is provided only once a native present has actually
    // been requested, so at preflight — before any frame exists — it is
    // absent by construction and the handshake is degraded on purpose.
    // Reading that as a capability Rosette failed to support is the wrong
    // conclusion, and the status alone cannot tell the two apart. A
    // *required* capability missing is the real defect, and it is called
    // out separately because it never has an innocent reading.
    if (response.statusValue() == .degraded) {
        if (!response.missing_required.isEmpty()) {
            machoCapturePrint(
                "macho-processor: Rosette GPU handshake #{d}: DEGRADED on a required capability; this is a real gap between what the caller must have and what this host provides\n",
                .{self.gpu_handshake_updates},
            );
        } else if (response.first_missing_capability != rosette_gpu.api.no_capability and
            @as(rosette_gpu.api.Capability, @enumFromInt(response.first_missing_capability)) == .presentation)
        {
            machoCapturePrint(
                "macho-processor: Rosette GPU handshake #{d}: degraded only on desired presentation, which is expected before a frame exists — Rosette declines to advertise presentation until a native present has been requested, so this is a refusal to claim an unproven capability rather than a missing one. It is worth reading only if it is still degraded after a present was attempted\n",
                .{self.gpu_handshake_updates},
            );
        } else {
            machoCapturePrint(
                "macho-processor: Rosette GPU handshake #{d}: degraded on a desired capability the caller can proceed without; nothing required is missing\n",
                .{self.gpu_handshake_updates},
            );
        }
    }
    // Name every capability the negotiation did not get, not just the
    // first.
    //
    // `status=degraded ... first_missing=memory_host_visible` says the
    // handshake settled for less than it asked for and names one item. A
    // reader cannot tell from that whether one capability is missing or
    // eleven, nor which of them the run will actually need. Each missing
    // desired capability gets a row, so the degradation is a list a reader
    // can work through rather than a single word.
    if (!response.missing_desired.isEmpty() or !response.missing_required.isEmpty()) {
        var shown: usize = 0;
        for (0..rosette_gpu.api.capability_count) |index| {
            const capability: rosette_gpu.api.Capability = @enumFromInt(index);
            const required = response.missing_required.contains(capability);
            const desired = response.missing_desired.contains(capability);
            if (!required and !desired) continue;
            if (shown >= 24) break;
            shown += 1;
            machoCapturePrint(
                "  gpu-capability missing {s: <28} class={s} negotiated={s}; {s}\n",
                .{
                    rosette_gpu.api.capabilityName(capability),
                    if (required) "REQUIRED" else "desired",
                    if (response.negotiated.contains(capability)) "YES" else "NO",
                    if (required)
                        "the profile declared this mandatory and the backend did not provide it; every operation that needs it will fail rather than degrade"
                    else
                        "asked for and not granted. The run continues without it, so the question a reader has to answer is which path silently takes a slower or lossier route because of it",
                },
            );
        }
    }

    // Once the guest device exists, this is no longer an advisory
    // observation. The device profile has no desired-only requirements,
    // so every non-success result is a foundational bridge violation.
    if (guest_device_authoritative and response.statusValue() != .success) {
        self.faultOnGpuHandshake(response, reason);
    }

    const health = self.gpu_runtime.bridgeHealth();
    const health_fingerprint = health.fingerprint();
    if (health_fingerprint != self.gpu_health_fingerprint) {
        self.gpu_health_fingerprint = health_fingerprint;
        machoCapturePrint(
            "macho-processor: Rosette GPU bridge health: stage={s} advisory_only=YES host_execution_ready={s} first_missing={s} authentic_submit={s} authentic_present={s}; this report is non-fatal and does not alter guest GPU bootstrap\n",
            .{
                @tagName(health.stage),
                if (health.readyForHostExecution()) "YES" else "NO",
                if (health.first_missing_execution_capability) |missing|
                    rosette_gpu.api.capabilityName(missing)
                else
                    "none",
                if (health.authentic_submission_seen) "YES" else "NO",
                if (health.authentic_presentation_seen) "YES" else "NO",
            },
        );
    }
}

pub fn createMetalSurface(self: anytype, state: anytype, library_token: u64, instance: u64, create_info: u64, output: u64) u64 {
    self.vulkan_presenter_stage = .metal_surface_requested;
    const info = state.guestMemoryConst(create_info, 32);
    const s_type = if (info != null) state.read32(create_info) else 0;
    const layer = if (info != null) state.read64(create_info + 24) else 0;
    self.vulkan_surface_path.noteDispatchAttempt(instance, layer);
    if (guest_context.field(state, "active_idle_source").* == 0) self.vulkan_presenter_off_ui_calls +|= 1;
    machoCapturePrint(
        "macho-processor: Vulkan presenter bind: stage=metal_surface_requested step={d} thread=0x{x} gtk_idle_source={d} instance=0x{x} create_info=0x{x} s_type={d} layer=0x{x} output=0x{x}\n",
        .{ state.executed_steps, guest_context.field(state, "active_guest_thread").*, guest_context.field(state, "active_idle_source").*, instance, create_info, s_type, layer, output },
    );
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    const layer_valid = if (info == null or layer == 0)
        false
    else if (@hasDecl(State, "validateNativeMetalLayerToken"))
        state.validateNativeMetalLayerToken(layer)
    else
        true;
    if (info == null or s_type != VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT or !layer_valid) {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason={s} create_info=0x{x} s_type={d} expected={d}\n",
            .{ if (info == null) "unmapped_create_info" else if (s_type != VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT) "unexpected_s_type" else if (layer == 0) "null_metal_layer" else "unbound_native_metal_layer", create_info, s_type, VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT },
        );
        return self.recordSurfacePathResult(state, vkErrorInitializationFailed(), output);
    }
    // Prefer a surface created from the guest's real VkInstance. A
    // VkSurfaceKHR is instance-owned; using the native presenter's shadow
    // instance here makes a later real vkCreateSwapchainKHR invalid even
    // though the surface-creation call itself succeeds.
    const real_surface = self.createRealGuestMetalSurface(state, instance, layer);
    if (real_surface.enforced and real_surface.result != 0) {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason=guest_instance_vkCreateMetalSurfaceEXT_failed VkResult={d} layer=0x{x}\n",
            .{ real_surface.result, layer },
        );
        return self.recordSurfacePathResult(state, @as(u32, @bitCast(real_surface.result)), output);
    }
    const native_surface = if (real_surface.enforced)
        NativeSurfaceResult{ .enforced = false, .result = 0, .surface = 0 }
    else
        self.createNativeMetalSurface(state, library_token);
    if (native_surface.enforced and native_surface.result != 0) {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind failed: stage=metal_surface reason=host_vkCreateMetalSurfaceEXT_failed VkResult={d} layer=0x{x}\n",
            .{ native_surface.result, layer },
        );
        return self.recordSurfacePathResult(state, @as(u32, @bitCast(native_surface.result)), output);
    }
    const result = createHandle(state, output, VK_SYNTHETIC_SURFACE, "Vulkan Metal surface");
    if (result == 0) {
        self.vulkan_metal_surfaces_created +|= 1;
        self.vulkan_presenter_stage = .metal_surface_created;
        if (@hasDecl(State, "noteNativeVulkanSurfaceBound")) {
            const host_surface = if (real_surface.enforced) real_surface.surface else native_surface.surface;
            state.noteNativeVulkanSurfaceBound(layer, VK_SYNTHETIC_SURFACE, host_surface);
        }
        if (self.vulkan_metal_surfaces_created == 1) {
            machoCapturePrint(
                "macho-processor: Vulkan milestone: metal_surface_created guest_surface=0x{x} backing={s} layer=0x{x} output=0x{x} gtk_idle_source={d}\n",
                .{ VK_SYNTHETIC_SURFACE, if (real_surface.enforced) "real_guest_instance" else "native_presenter_shadow", layer, output, guest_context.field(state, "active_idle_source").* },
            );
        }
        // A shadow diagnostic swapchain would be a second Vulkan owner
        // of the same CAMetalLayer. Once the guest's own VkInstance has
        // a real surface, keep that graph authoritative and do not ask a
        // second swapchain to compete for the drawable pool.
        if (shouldBringUpNativePresenter(real_surface)) {
            _ = self.bringUpNativePresenter(state, library_token);
        } else {
            machoCapturePrint(
                "macho-processor: native Vulkan presenter suppressed: the guest VkInstance owns the real CAMetalLayer surface; only one swapchain may consume its drawable pool\n",
                .{},
            );
        }
    } else {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
    }
    return self.recordSurfacePathResult(state, result, output);
}

pub fn recordSurfacePathResult(self: anytype, state: anytype, result: u64, output: u64) u64 {
    const vk_result: i32 = @bitCast(@as(u32, @truncate(result)));
    const surface = if (result == 0 and output != 0 and state.guestMemoryConst(output, 8) != null)
        state.read64(output)
    else
        0;
    self.vulkan_surface_path.noteDispatchResult(vk_result, surface);
    return result;
}

pub fn createRealGuestMetalSurface(self: anytype, state: anytype, guest_instance: u64, layer_token: u64) NativeSurfaceResult {
    const instance = self.real_vulkan.instance orelse return .{ .enforced = false, .result = 0, .surface = 0 };
    const known_guest_instance = if (self.real_vulkan.guest_instance_handle != 0)
        self.real_vulkan.guest_instance_handle
    else
        @intFromPtr(instance);
    if (guest_instance == 0 or (guest_instance != known_guest_instance and guest_instance != @intFromPtr(instance))) {
        return .{ .enforced = false, .result = 0, .surface = 0 };
    }
    const State = @typeInfo(@TypeOf(state)).pointer.child;
    if (!@hasDecl(State, "nativeMetalLayerHostPointer")) {
        return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
    }
    const host_layer = state.nativeMetalLayerHostPointer();
    if (host_layer == 0) {
        return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
    }
    if (self.real_vulkan.surface != 0) {
        return .{ .enforced = true, .result = 0, .surface = self.real_vulkan.surface };
    }
    const get_proc = self.real_vulkan.get_instance_proc_addr orelse {
        return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
    };
    const address = get_proc(instance, "vkCreateMetalSurfaceEXT") orelse {
        return .{ .enforced = true, .result = vkErrorInitializationFailedSigned(), .surface = 0 };
    };
    const create_surface: abi.PfnCreateMetalSurfaceEXT = @ptrCast(@alignCast(address));
    const create_info = abi.MetalSurfaceCreateInfoEXT{ .layer = @ptrFromInt(host_layer) };
    var surface: abi.SurfaceKHR = 0;
    const result = create_surface(instance, &create_info, null, &surface);
    if (result != abi.SUCCESS or surface == 0) {
        machoCapturePrint(
            "macho-processor: REAL guest vkCreateMetalSurfaceEXT failed: VkResult={d} instance=0x{x} CAMetalLayer=0x{x} layer_token=0x{x}\n",
            .{ result, guest_instance, host_layer, layer_token },
        );
        return .{ .enforced = true, .result = if (result != 0) result else vkErrorInitializationFailedSigned(), .surface = 0 };
    }
    self.real_vulkan.surface = surface;
    self.present_chain.noteSurface(surface, host_layer, .guest);
    machoCapturePrint(
        "macho-processor: REAL guest vkCreateMetalSurfaceEXT succeeded: instance=0x{x} CAMetalLayer=0x{x} VkSurfaceKHR=0x{x}\n",
        .{ guest_instance, host_layer, surface },
    );
    return .{ .enforced = true, .result = 0, .surface = surface };
}

pub fn shouldBringUpNativePresenter(real_surface: NativeSurfaceResult) bool {
    return !real_surface.enforced;
}

pub fn guestDeviceMatches(self: anytype, guest_device: u64) bool {
    if (guest_device == 0) return false;
    if (self.real_vulkan.device_lost) return false;
    // The synthetic presenter path intentionally has no native VkDevice;
    // it still needs a provenance check so a stale/foreign handle cannot
    // create a swapchain.  Native handles continue through the real-device
    // checks below.
    if (guest_device == VK_SYNTHETIC_DEVICE) return self.vulkan_logical_devices_created != 0;
    if (!self.real_vulkan.hasDevice()) return false;
    if (guest_device == self.real_vulkan.guest_device_handle) return true;
    const real_device = self.real_vulkan.device orelse return false;
    if (guest_device == @intFromPtr(real_device)) return true;
    // There is one guest logical device in the current Xenia Vulkan path.
    // A compatibility thunk may rewrite the dispatchable value after
    // vkCreateDevice; keep the native object graph alive instead of
    // reporting the misleading logical_device_not_created failure.
    return self.vulkan_logical_devices_created != 0;
}

pub fn createSwapchain(self: anytype, state: anytype, device: u64, create_info: u64, output: u64) u64 {
    self.vulkan_presenter_bind_attempts +|= 1;
    self.vulkan_presenter_stage = .swapchain_requested;
    const info = state.guestMemoryConst(create_info, VK_SWAPCHAIN_CREATE_INFO_SIZE);
    const s_type = if (info != null) state.read32(create_info) else 0;
    const surface = if (info != null) state.read64(create_info + 24) else 0;
    const image_width = if (info != null) state.read32(create_info + 44) else 0;
    const image_height = if (info != null) state.read32(create_info + 48) else 0;
    const image_usage = if (info != null) state.read32(create_info + 56) else 0;
    if (guest_context.field(state, "active_idle_source").* == 0) self.vulkan_presenter_off_ui_calls +|= 1;
    machoCapturePrint(
        "macho-processor: Vulkan presenter bind: stage=swapchain_requested attempt={d} step={d} thread=0x{x} gtk_idle_source={d} device=0x{x} create_info=0x{x} s_type={d} surface=0x{x} output=0x{x}\n",
        .{ self.vulkan_presenter_bind_attempts, state.executed_steps, guest_context.field(state, "active_guest_thread").*, guest_context.field(state, "active_idle_source").*, device, create_info, s_type, surface, output },
    );
    if (!self.real_vulkan.hasDevice() and self.real_vulkan.hasInstance() and
        self.native_vulkan_library_token != 0)
    {
        // The normal path creates the device at the guest's
        // vkCreateDevice call. A few translated loader paths have been
        // observed to lose that dispatch but still reach swapchain
        // creation. Build the minimum real device against the already
        // created guest instance, using a temporary guest output slot;
        // all subsequent objects remain children of that real device.
        if (state.guestAlloc(8, 8)) |temporary_output| {
            const recovery = self.ensureRealDevice(state, self.native_vulkan_library_token, 0, 0, temporary_output);
            if (recovery == 0) {
                machoCapturePrint(
                    "macho-processor: Vulkan lazy device recovery: created real logical device before swapchain device=0x{x} guest_device=0x{x}\n",
                    .{ @intFromPtr(self.real_vulkan.device.?), state.read64(temporary_output) },
                );
            } else {
                machoCapturePrint(
                    "macho-processor: Vulkan lazy device recovery failed: VkResult={d}\n",
                    .{recovery},
                );
            }
        }
    }
    const failure_reason: ?[]const u8 = if (self.real_vulkan.device_lost)
        "device_lost"
    else if (!self.guestDeviceMatches(device))
        "logical_device_not_created"
    else if (self.vulkan_metal_surfaces_created == 0)
        "metal_surface_not_created"
    else if (info == null)
        "unmapped_create_info"
    else if (s_type != VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR)
        "unexpected_s_type"
    else if (state.read64(create_info + 8) != 0)
        "unsupported_pnext"
    else if (surface != VK_SYNTHETIC_SURFACE)
        "unknown_surface"
    else if (output == 0 or state.guestMemory(output, 8) == null)
        "unmapped_output"
    else
        null;
    if (failure_reason) |reason| {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
        machoCapturePrint(
            "macho-processor: Vulkan presenter bind failed: stage=swapchain attempt={d} reason={s} device=0x{x} surface=0x{x} s_type={d} output=0x{x}\n",
            .{ self.vulkan_presenter_bind_attempts, reason, device, surface, s_type, output },
        );
        return vkErrorInitializationFailed();
    }

    if (self.real_vulkan.hasDevice() and self.real_vulkan.surface != 0 and self.real_vulkan.fn_ptrs.create_swapchain != null and
        HandleMap.freeSlots(&self.real_vulkan.swapchain_map) == 0)
    {
        self.noteVulkanMapCapacityRefusal("vkCreateSwapchainKHR", 1, 0);
        return vkErrorOutOfHostMemory();
    }

    // When the guest's device and Metal surface were both created on the
    // real instance, create the swapchain on that same driver object. The
    // guest still receives a stable Rosette handle, while every later
    // acquire/submit/present call can resolve it through this map.
    if (self.real_vulkan.hasDevice() and self.real_vulkan.surface != 0 and self.real_vulkan.fn_ptrs.create_swapchain != null) {
        const real_device = self.real_vulkan.device.?;
        const real_surface = self.real_vulkan.surface;
        var real_info: abi.SwapchainCreateInfoKHR = .{};
        real_info.flags = state.read32(create_info + 16);
        real_info.surface = real_surface;
        real_info.min_image_count = state.read32(create_info + 32);
        real_info.image_format = state.read32(create_info + 36);
        real_info.image_color_space = state.read32(create_info + 40);
        real_info.image_extent = .{ .width = image_width, .height = image_height };
        real_info.image_array_layers = state.read32(create_info + 52);
        real_info.image_usage = image_usage;
        real_info.image_sharing_mode = state.read32(create_info + 60);
        real_info.pre_transform = state.read32(create_info + 80);
        real_info.composite_alpha = state.read32(create_info + 84);
        real_info.present_mode = state.read32(create_info + 88);
        real_info.clipped = state.read32(create_info + 92);
        const old_synthetic = state.read64(create_info + 96);
        real_info.old_swapchain = self.real_vulkan.realSwapchain(old_synthetic) orelse 0;

        // Establish the guest-requested extent before asking the native
        // surface for capabilities. On macOS the current extent is often
        // derived directly from CAMetalLayer.drawableSize; if the bridge
        // is still at a Retina-sized value, querying first simply turns
        // that disagreement into the host swapchain's official extent.
        if (!self.prepareMetalDrawableForSwapchain(state, image_width, image_height)) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            return vkErrorInitializationFailed();
        }

        // The guest's capability query and the host's surface query can
        // differ slightly (especially after a resize).  Validate the
        // request against the real surface immediately before creating
        // the swapchain and choose the nearest legal value.  Passing the
        // synthetic capability answer through unchanged is exactly how a
        // real device still ends up returning VK_ERROR_* at this seam.
        const get_proc = self.real_vulkan.get_instance_proc_addr orelse return vkErrorInitializationFailed();
        const get_caps_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") orelse return vkErrorInitializationFailed();
        const get_caps: abi.PfnGetPhysicalDeviceSurfaceCapabilitiesKHR = @ptrCast(@alignCast(get_caps_address));
        var caps: abi.SurfaceCapabilitiesKHR = .{};
        const caps_result = get_caps(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &caps);
        self.noteRealVulkanResult(caps_result, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
        if (caps_result != abi.SUCCESS) return @as(u32, @bitCast(caps_result));
        const requested_extent = abi.Extent2D{ .width = image_width, .height = image_height };
        const resolved_extent = if (caps.current_extent.width != abi.extent_undefined and
            caps.current_extent.height != abi.extent_undefined)
            caps.current_extent
        else
            abi.Extent2D{
                .width = @max(caps.min_image_extent.width, @min(image_width, caps.max_image_extent.width)),
                .height = @max(caps.min_image_extent.height, @min(image_height, caps.max_image_extent.height)),
            };
        if (!rosette_gpu.vulkan.selection.extentMatches(resolved_extent, requested_extent)) {
            // A fixed backing-pixel extent is not a harmless adjustment
            // here. Xenia already asked for a precise guest surface size,
            // and accepting the driver's 2560x1440 answer would make the
            // real swapchain disagree with the guest's 1280x720 contract
            // even though vkCreateSwapchainKHR may return success. Stop
            // before any real guest swapchain is published.
            machoCapturePrint(
                "macho-processor: REAL vkCreateSwapchainKHR refused: drawable extent contract mismatch requested={d}x{d} driver={d}x{d} current={d}x{d} bounds={d}x{d}..{d}x{d}; a fixed or clamped host extent may not replace the guest request\n",
                .{
                    image_width,
                    image_height,
                    resolved_extent.width,
                    resolved_extent.height,
                    caps.current_extent.width,
                    caps.current_extent.height,
                    caps.min_image_extent.width,
                    caps.min_image_extent.height,
                    caps.max_image_extent.width,
                    caps.max_image_extent.height,
                },
            );
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            self.noteGraphicsExtentContractFailure(
                state,
                image_width,
                image_height,
                resolved_extent.width,
                resolved_extent.height,
                "guest_surface_extent_mismatch",
            );
            return vkErrorInitializationFailed();
        }
        real_info.image_extent = resolved_extent;
        // Recheck the actual CAMetalLayer immediately before the driver
        // create call. This catches a layout/backing-property transition
        // between the first preflight and the capability query.
        if (!self.prepareMetalDrawableForSwapchain(state, resolved_extent.width, resolved_extent.height)) {
            self.vulkan_presenter_stage = .failed;
            self.vulkan_presenter_bind_failures +|= 1;
            return vkErrorInitializationFailed();
        }
        real_info.min_image_count = @max(real_info.min_image_count, caps.min_image_count);
        if (caps.max_image_count != abi.image_count_unbounded) real_info.min_image_count = @min(real_info.min_image_count, caps.max_image_count);
        real_info.image_array_layers = @max(real_info.image_array_layers, 1);
        if (caps.max_image_array_layers != 0) real_info.image_array_layers = @min(real_info.image_array_layers, caps.max_image_array_layers);
        const requested_usage = real_info.image_usage;
        real_info.image_usage &= caps.supported_usage_flags;
        if (real_info.image_usage == 0) {
            machoCapturePrint("macho-processor: REAL vkCreateSwapchainKHR refused: no supported usage bits requested=0x{x} supported=0x{x}\n", .{ requested_usage, caps.supported_usage_flags });
            return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        }
        // A readback is diagnostic only, but adding TRANSFER_SRC to the
        // host swapchain is legal when the surface advertises it and lets
        // the probe inspect the exact acquired image without touching the
        // guest's logical usage bits.  If the surface does not support it,
        // the run remains fully valid and the log says pixel=unavailable.
        if ((caps.supported_usage_flags & abi.IMAGE_USAGE_TRANSFER_SRC_BIT) != 0) {
            real_info.image_usage |= abi.IMAGE_USAGE_TRANSFER_SRC_BIT;
        }
        const requested_transform = real_info.pre_transform;
        if ((caps.supported_transforms & requested_transform) == 0) real_info.pre_transform = caps.current_transform;
        const requested_composite = real_info.composite_alpha;
        if ((caps.supported_composite_alpha & requested_composite) == 0) real_info.composite_alpha = caps.supported_composite_alpha & (~caps.supported_composite_alpha +% 1);

        var host_formats: [32]abi.SurfaceFormatKHR = [_]abi.SurfaceFormatKHR{.{}} ** 32;
        var host_format_count: u32 = @intCast(host_formats.len);
        const get_formats_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfaceFormatsKHR") orelse return vkErrorInitializationFailed();
        const get_formats: abi.PfnGetPhysicalDeviceSurfaceFormatsKHR = @ptrCast(@alignCast(get_formats_address));
        const formats_result = get_formats(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &host_format_count, &host_formats);
        self.noteRealVulkanResult(formats_result, "vkGetPhysicalDeviceSurfaceFormatsKHR");
        if (formats_result != abi.SUCCESS and formats_result != abi.INCOMPLETE) return @as(u32, @bitCast(formats_result));
        const format_count = @min(host_format_count, @as(u32, @intCast(host_formats.len)));
        var matching_format = false;
        for (host_formats[0..format_count]) |format| {
            if (format.format == real_info.image_format and format.color_space == real_info.image_color_space) {
                matching_format = true;
                break;
            }
        }
        if (!matching_format) {
            if (format_count == 0) return @as(u32, @bitCast(abi.ERROR_FORMAT_NOT_SUPPORTED));
            real_info.image_format = host_formats[0].format;
            real_info.image_color_space = host_formats[0].color_space;
        }

        var host_modes: [16]u32 = [_]u32{0} ** 16;
        var host_mode_count: u32 = @intCast(host_modes.len);
        const get_modes_address = get_proc(self.real_vulkan.instance orelse return vkErrorInitializationFailed(), "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return vkErrorInitializationFailed();
        const get_modes: abi.PfnGetPhysicalDeviceSurfacePresentModesKHR = @ptrCast(@alignCast(get_modes_address));
        const modes_result = get_modes(self.real_vulkan.physical_device orelse return vkErrorInitializationFailed(), real_surface, &host_mode_count, &host_modes);
        self.noteRealVulkanResult(modes_result, "vkGetPhysicalDeviceSurfacePresentModesKHR");
        if (modes_result != abi.SUCCESS and modes_result != abi.INCOMPLETE) return @as(u32, @bitCast(modes_result));
        const mode_count = @min(host_mode_count, @as(u32, @intCast(host_modes.len)));
        var matching_mode = false;
        var fifo_mode = false;
        for (host_modes[0..mode_count]) |mode| {
            if (mode == real_info.present_mode) matching_mode = true;
            if (mode == abi.PRESENT_MODE_FIFO_KHR) fifo_mode = true;
        }
        if (!matching_mode) {
            if (fifo_mode) {
                real_info.present_mode = abi.PRESENT_MODE_FIFO_KHR;
            } else if (mode_count != 0) {
                real_info.present_mode = host_modes[0];
            } else {
                return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            }
        }

        // Concurrent sharing carries a guest pointer. Copy the indices to
        // host-owned storage instead of allowing the driver to dereference
        // an x86 guest address after this call returns.
        var queue_indices: [16]u32 = [_]u32{0} ** 16;
        const guest_queue_count = state.read32(create_info + 64);
        const guest_queue_address = state.read64(create_info + 72);
        const queue_count = @min(guest_queue_count, queue_indices.len);
        if (real_info.image_sharing_mode != abi.SHARING_MODE_EXCLUSIVE and queue_count != 0 and guest_queue_address != 0) {
            if (state.guestMemoryConst(guest_queue_address, @as(u64, queue_count) * 4)) |queue_bytes| {
                var valid_indices = true;
                for (0..queue_count) |index| {
                    queue_indices[index] = std.mem.readInt(u32, queue_bytes[index * 4 ..][0..4], .little);
                    if (queue_indices[index] >= self.real_vulkan.queue_family_count) valid_indices = false;
                }
                if (valid_indices) {
                    real_info.queue_family_index_count = queue_count;
                    real_info.queue_family_indices = &queue_indices;
                } else {
                    real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
                    real_info.queue_family_index_count = 0;
                }
            } else {
                real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
                real_info.queue_family_index_count = 0;
            }
        } else {
            real_info.image_sharing_mode = abi.SHARING_MODE_EXCLUSIVE;
            real_info.queue_family_index_count = 0;
        }

        var real_swapchain: abi.SwapchainKHR = 0;
        const real_result = self.real_vulkan.fn_ptrs.create_swapchain.?(real_device, &real_info, null, &real_swapchain);
        self.noteRealVulkanResult(real_result, "vkCreateSwapchainKHR");
        if (real_result != abi.SUCCESS or real_swapchain == 0) {
            machoCapturePrint(
                "macho-processor: REAL vkCreateSwapchainKHR failed: VkResult={d} device=0x{x} surface=0x{x} requested_extent={d}x{d} resolved_extent={d}x{d} format={d} usage=0x{x}\n",
                .{ real_result, device, surface, image_width, image_height, real_info.image_extent.width, real_info.image_extent.height, real_info.image_format, image_usage },
            );
            return @as(u32, @bitCast(real_result));
        }
        const synthetic_swapchain = self.nextVulkanObject();
        if (self.real_vulkan.allocateSwapchainRecord(synthetic_swapchain, real_swapchain) == null) {
            if (self.real_vulkan.fn_ptrs.destroy_swapchain) |destroy| destroy(real_device, real_swapchain, null);
            return @as(u32, @bitCast(abi.ERROR_OUT_OF_HOST_MEMORY));
        }
        if (!self.mapVulkanHandle(&self.real_vulkan.swapchain_map, synthetic_swapchain, real_swapchain, "vkCreateSwapchainKHR")) {
            if (self.real_vulkan.mutableSwapchainRecord(synthetic_swapchain)) |record| record.* = .{};
            if (self.real_vulkan.fn_ptrs.destroy_swapchain) |destroy| destroy(real_device, real_swapchain, null);
            return vkErrorOutOfHostMemory();
        }
        state.write64(output, synthetic_swapchain);
        registerOpaqueHandle(state, synthetic_swapchain, "Vulkan swapchain");
        self.real_vulkan.swapchain = real_swapchain;
        if (real_info.old_swapchain != 0) self.present_chain.retireSwapchain(real_info.old_swapchain);
        self.present_chain.noteSwapchain(.{
            .handle = real_swapchain,
            .surface = real_surface,
            .owner = .guest,
            .width = real_info.image_extent.width,
            .height = real_info.image_extent.height,
            .format = real_info.image_format,
            .present_mode = real_info.present_mode,
            .image_count = real_info.min_image_count,
            .image_usage = real_info.image_usage,
            .requested_image_usage = image_usage,
        });
        self.vulkan_swapchains_created +|= 1;
        self.vulkan_swapchain_image_count = 0;
        self.vulkan_tiers.note(.swapchain, .real);
        self.vulkan_presenter_stage = .guest_swapchain_ready;
        machoCapturePrint(
            "macho-processor: REAL vkCreateSwapchainKHR succeeded: synthetic=0x{x} real=0x{x} requested_extent={d}x{d} resolved_extent={d}x{d} format={d} usage=0x{x}\n",
            .{ synthetic_swapchain, real_swapchain, image_width, image_height, real_info.image_extent.width, real_info.image_extent.height, real_info.image_format, image_usage },
        );
        self.yieldMetalDrawableToSwapchain(state, real_info.image_extent.width, real_info.image_extent.height);
        // Swapchain creation alone is not picture evidence. Keep the
        // Rosette presenter alive until the guest has either submitted a
        // content-bearing Vulkan frame or the console front-buffer
        // handoff succeeds; otherwise a later VdSwap has no screen owner
        // when Xenia's RefreshGuestOutput path is absent.
        if (self.native_presenter.stage.isReady()) {
            machoCapturePrint(
                "macho-processor: native presenter retained after guest swapchain creation: extent={d}x{d}; no guest content has been proven yet, so the VdSwap/front-buffer fallback remains armed\n",
                .{ real_info.image_extent.width, real_info.image_extent.height },
            );
        }
        return 0;
    }

    // The synthetic path still shares the real CAMetalLayer with the
    // native presenter/fallback. It cannot skip the same exact-size
    // handshake merely because no host VkSwapchainKHR is being created;
    // otherwise its first diagnostic frame can silently establish a
    // different drawable geometry than the guest requested.
    if (!self.prepareMetalDrawableForSwapchain(state, image_width, image_height)) {
        self.vulkan_presenter_stage = .failed;
        self.vulkan_presenter_bind_failures +|= 1;
        return vkErrorInitializationFailed();
    }
    const handle = self.nextVulkanObject();
    state.write64(output, handle);
    registerOpaqueHandle(state, handle, "Vulkan swapchain");
    self.vulkan_swapchains_created +|= 1;
    self.vulkan_swapchain_image_count = 3;
    for (self.vulkan_swapchain_image_handles[0..self.vulkan_swapchain_image_count]) |*image| {
        if (image.* == 0) {
            image.* = self.nextVulkanObject();
            registerOpaqueHandle(state, image.*, "Vulkan swapchain image");
        }
    }
    if (self.vulkan_swapchains_created == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan milestone: swapchain_created handle=0x{x} output=0x{x} images={d} extent={d}x{d} usage=0x{x} backing=synthetic\n",
            .{ handle, output, self.vulkan_swapchain_image_count, image_width, image_height, image_usage },
        );
    }
    self.vulkan_presenter_stage = .synthetic_swapchain_ready;
    machoCapturePrint(
        "macho-processor: Vulkan presenter bind complete: stage=synthetic_swapchain_ready attempt={d} surface=0x{x} swapchain=0x{x} gtk_idle_source={d} native_drawable=false\n",
        .{ self.vulkan_presenter_bind_attempts, surface, handle, guest_context.field(state, "active_idle_source").* },
    );
    if (self.vulkan_swapchains_created == 1) {
        machoCapturePrint(
            "macho-processor: GRAPHICS FORWARDING BOUNDARY: native Vulkan device creation was unavailable, so the guest's VkDevice, VkSwapchainKHR, swapchain images, commands, queue submissions and presents are using the diagnostic synthetic fallback (stage={s}); no guest command reaches a driver. Guest pixels require the native Vulkan path or a title-owned framebuffer handoff.\n",
            .{@tagName(self.native_presenter.stage)},
        );
    }
    _ = self.presentWindowFrame(state, handle, image_width, image_height, 1);
    return 0;
}

pub fn enumerateSwapchainImages(self: anytype, state: anytype) u64 {
    const count_address = guest_context.registers(state).rdx;
    if (count_address == 0 or state.guestMemory(count_address, 4) == null) return vkErrorInitializationFailed();

    if (self.real_vulkan.hasDevice() and self.real_vulkan.realSwapchain(guest_context.registers(state).rsi) != null and self.real_vulkan.fn_ptrs.get_swapchain_images != null) {
        const real_swapchain = self.real_vulkan.realSwapchain(guest_context.registers(state).rsi).?;
        const record = self.real_vulkan.mutableSwapchainRecord(guest_context.registers(state).rsi) orelse
            return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        var real_count: u32 = 0;
        var result = self.real_vulkan.fn_ptrs.get_swapchain_images.?(self.real_vulkan.device.?, real_swapchain, &real_count, null);
        self.noteRealVulkanResult(result, "vkGetSwapchainImagesKHR");
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
        const exposed_count: u32 = @min(real_count, record.image_handles.len);
        record.image_count = exposed_count;
        self.vulkan_swapchain_image_count = exposed_count;
        if (guest_context.registers(state).rcx == 0) {
            state.write32(count_address, exposed_count);
            self.vulkan_tiers.note(.swapchain, .real);
            return 0;
        }
        const capacity = state.read32(count_address);
        const written: u32 = @min(@min(capacity, exposed_count), record.image_handles.len);
        if (written != 0 and state.guestMemory(guest_context.registers(state).rcx, @as(u64, written) * 8) == null) return vkErrorInitializationFailed();
        var real_images: [MAX_SWAPCHAIN_IMAGES]abi.Image = [_]abi.Image{0} ** MAX_SWAPCHAIN_IMAGES;
        var driver_count = written;
        result = self.real_vulkan.fn_ptrs.get_swapchain_images.?(self.real_vulkan.device.?, real_swapchain, &driver_count, &real_images);
        self.noteRealVulkanResult(result, "vkGetSwapchainImagesKHR");
        if (result != abi.SUCCESS and result != abi.INCOMPLETE) return @as(u32, @bitCast(result));
        const actual: u32 = @min(@min(driver_count, written), exposed_count);
        var new_image_mappings: usize = 0;
        for (0..@as(usize, @intCast(actual))) |index| {
            if (record.image_handles[index] == 0) new_image_mappings += 1;
        }
        const available_image_mappings = HandleMap.freeSlots(&self.real_vulkan.image_map);
        if (available_image_mappings < new_image_mappings) {
            self.noteVulkanMapCapacityRefusal("vkGetSwapchainImagesKHR", new_image_mappings, available_image_mappings);
            return vkErrorOutOfHostMemory();
        }
        var newly_mapped_images: [MAX_SWAPCHAIN_IMAGES]u64 = [_]u64{0} ** MAX_SWAPCHAIN_IMAGES;
        var newly_mapped_count: usize = 0;
        for (0..actual) |index| {
            var synthetic = record.image_handles[index];
            const was_new = synthetic == 0;
            if (synthetic == 0) {
                synthetic = self.nextVulkanObject();
                record.image_handles[index] = synthetic;
                registerOpaqueHandle(state, synthetic, "Vulkan swapchain image");
            }
            if (!self.mapVulkanHandle(&self.real_vulkan.image_map, synthetic, real_images[index], "vkGetSwapchainImagesKHR")) {
                if (was_new) record.image_handles[index] = 0;
                for (newly_mapped_images[0..newly_mapped_count]) |mapped| {
                    _ = self.releaseVulkanHandle(&self.real_vulkan.image_map, mapped);
                    for (&record.image_handles) |*image| {
                        if (image.* == mapped) image.* = 0;
                    }
                }
                return vkErrorOutOfHostMemory();
            }
            if (was_new) {
                newly_mapped_images[newly_mapped_count] = synthetic;
                newly_mapped_count += 1;
            }
            state.write64(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8, synthetic);
        }
        self.present_chain.noteSwapchainImages(real_swapchain, real_images[0..@as(usize, @intCast(actual))]);
        state.write32(count_address, actual);
        self.vulkan_swapchain_images_enumerated +|= actual;
        self.vulkan_tiers.note(.swapchain, .real);
        // The driver's VK_INCOMPLETE only says it has more images than the
        // bridge can name, and the probe already told the guest the smaller
        // number. Reporting it here would tell a caller its correctly sized
        // array was too small, and the standard two-call loop would ask
        // again with the same size for the rest of the run.
        return @as(u32, @bitCast(if (actual < exposed_count) abi.INCOMPLETE else abi.SUCCESS));
    }

    const count = if (self.vulkan_swapchain_image_count == 0) 3 else self.vulkan_swapchain_image_count;
    if (guest_context.registers(state).rcx == 0) {
        state.write32(count_address, count);
        return 0;
    }
    const requested = state.read32(count_address);
    const written: u32 = @min(requested, count);
    if (state.guestMemory(guest_context.registers(state).rcx, @as(u64, written) * 8) == null) return vkErrorInitializationFailed();
    for (0..written) |index| {
        var handle = self.vulkan_swapchain_image_handles[index];
        if (handle == 0) {
            handle = self.nextVulkanObject();
            self.vulkan_swapchain_image_handles[index] = handle;
            registerOpaqueHandle(state, handle, "Vulkan swapchain image");
        }
        state.write64(guest_context.registers(state).rcx + @as(u64, @intCast(index)) * 8, handle);
    }
    state.write32(count_address, written);
    self.vulkan_swapchain_images_enumerated +|= written;
    if (self.vulkan_swapchain_images_enumerated == written) {
        machoCapturePrint(
            "macho-processor: Vulkan milestone: swapchain_images count={d} output=0x{x}\n",
            .{ written, guest_context.registers(state).rcx },
        );
    }
    return if (written < count) 5 else 0;
}

pub fn acquireNextImage(self: anytype, state: anytype, output: u64) u64 {
    if (output == 0 or state.guestMemory(output, 4) == null) return vkErrorInitializationFailed();
    if (self.realDeviceLostResult()) |result| return result;

    if (self.real_vulkan.hasDevice() and self.real_vulkan.realSwapchain(guest_context.registers(state).rsi) != null and self.real_vulkan.fn_ptrs.acquire_next_image != null) {
        const semaphore = if (guest_context.registers(state).rcx == 0)
            0
        else
            self.real_vulkan.realSemaphore(guest_context.registers(state).rcx) orelse return vkErrorInitializationFailed();
        const fence = if (guest_context.registers(state).r8 == 0)
            0
        else
            self.real_vulkan.realFence(guest_context.registers(state).r8) orelse return vkErrorInitializationFailed();
        var image_index: u32 = 0;
        const result = self.real_vulkan.fn_ptrs.acquire_next_image.?(
            self.real_vulkan.device.?,
            self.real_vulkan.realSwapchain(guest_context.registers(state).rsi).?,
            guest_context.registers(state).rdx,
            semaphore,
            fence,
            &image_index,
        );
        self.noteRealVulkanResult(result, "vkAcquireNextImageKHR");
        if (result != abi.SUCCESS and result != abi.SUBOPTIMAL_KHR) return @as(u32, @bitCast(result));
        state.write32(output, image_index);
        self.present_chain.noteAcquire(
            self.real_vulkan.realSwapchain(guest_context.registers(state).rsi) orelse 0,
            image_index,
        );
        self.vulkan_images_acquired +|= 1;
        self.vulkan_tiers.note(.swapchain, .real);
        return @as(u32, @bitCast(result));
    }

    state.write32(output, 0);
    self.vulkan_images_acquired +|= 1;
    if (self.vulkan_images_acquired == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan milestone: first_image_acquired index=0 output=0x{x}\n",
            .{output},
        );
    }
    return 0;
}

pub fn queueSubmit(self: anytype, state: anytype) u64 {
    if (self.native_texture_state) |native| {
        if (native.terminal_result != abi.SUCCESS) self.noteRealVulkanResult(native.terminal_result, "native Metal texture resources");
    }
    self.vulkan_queue_submits +|= 1;
    self.frame_provenance.noteGuestVulkanCall();
    if (self.realDeviceLostResult()) |result| return result;
    // Phase 1: forward real queue submissions when the device and queue exist.
    // The guest's vkQueueSubmit arguments:
    //   rdi = queue handle (synthetic)
    //   rsi = submit count
    //   rdx = pSubmits (guest pointer to VkSubmitInfo array)
    //   rcx = fence handle (synthetic, may be 0)
    if (self.real_vulkan.hasDevice()) {
        const real_queue = self.real_vulkan.realQueue(guest_context.registers(state).rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
        defer queue_lease.release();
        if (self.real_vulkan.fn_ptrs.queue_submit) |submit_fn| {
            const requested_count: u32 = @truncate(guest_context.registers(state).rsi);
            const submits_addr = guest_context.registers(state).rdx;
            const fence_synthetic = guest_context.registers(state).rcx;

            // `vkQueueSubmit(queue, 0, NULL, fence)` is a fence-only
            // submission and is entirely legal: it signals the fence once
            // everything already submitted to the queue has completed.
            // Xenia's presenter uses exactly that to close a guest-output
            // refresh (`AcquireFenceAndSubmit(..., 0, nullptr)`), so
            // refusing it leaves that fence unsignalled, the completion
            // timeline never advances past the submission, and every
            // later frame repeats the refusal forever.
            if (requested_count == 0) {
                const fence_real = if (fence_synthetic == 0)
                    0
                else
                    self.real_vulkan.realFence(fence_synthetic) orelse
                        return self.refuseVulkanCall(
                            "vkQueueSubmit",
                            "fence handle is not one Rosetta issued",
                            abi.ERROR_INITIALIZATION_FAILED,
                            .{ fence_synthetic, 0, 0 },
                        );
                // A submission with neither work nor a fence has no
                // observable effect at all; the driver accepts it and so
                // does this, without a round trip.
                if (fence_real == 0) return abi.SUCCESS;
                const result = submit_fn(real_queue, 0, null, fence_real);
                self.noteRealVulkanResult(result, "vkQueueSubmit");
                if (result != abi.SUCCESS) return @as(u32, @bitCast(result));
                self.vulkan_fence_only_queue_submits +|= 1;
                self.vulkan_fence_watch.noteSubmission(fence_synthetic);
                self.frame_provenance.noteNativeSubmission();
                self.vulkan_tiers.note(.queue_submission, .real);
                self.vulkan_real_queue_submits +|= 1;
                if (self.vulkan_fence_only_queue_submits == 1) {
                    machoCapturePrint(
                        "macho-processor: Vulkan milestone: first fence-only queue submit forwarded fence=0x{x}; the guest is closing a submission it will wait on\n",
                        .{fence_synthetic},
                    );
                }
                return 0;
            }
            // A non-zero count with a null array is genuinely invalid
            // (VUID-vkQueueSubmit-pSubmits-parameter), and is a different
            // fact from the legal empty submit above.
            if (submits_addr == 0) {
                return self.refuseVulkanCall(
                    "vkQueueSubmit",
                    "pSubmits is null with a non-zero submitCount",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ requested_count, 0, fence_synthetic },
                );
            }
            // The translation buffers are fixed-size. Submitting the
            // first `capacity` batches and reporting SUCCESS would drop
            // guest work silently, so a batch count this path cannot
            // carry is refused rather than truncated.
            const submit_count: u32 = requested_count;
            if (submit_count > 8) {
                return self.refuseVulkanCall(
                    "vkQueueSubmit",
                    "submitCount exceeds the batch translation capacity of 8",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ requested_count, 8, fence_synthetic },
                );
            }
            if (state.guestMemoryConst(submits_addr, @as(u64, submit_count) * @sizeOf(abi.SubmitInfo)) == null) {
                return self.refuseVulkanCall(
                    "vkQueueSubmit",
                    "pSubmits array is not readable guest memory",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ submits_addr, submit_count, fence_synthetic },
                );
            }
            if (!self.uploadMappedMemoryBeforeSubmit(state)) {
                return self.refuseVulkanCall(
                    "vkQueueSubmit",
                    "a mapped allocation could not be flushed to its real memory",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ submits_addr, submit_count, fence_synthetic },
                );
            }
            var real_submits: [8]abi.SubmitInfo = [_]abi.SubmitInfo{.{}} ** 8;
            var wait_semaphores: [8][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 8;
            var wait_stages: [8][16]u32 = [_][16]u32{[_]u32{0} ** 16} ** 8;
            var command_buffers: [8][256]abi.CommandBuffer = [_][256]abi.CommandBuffer{[_]abi.CommandBuffer{null} ** 256} ** 8;
            var command_synthetics: [8][256]u64 = [_][256]u64{[_]u64{0} ** 256} ** 8;
            var command_counts: [8]u32 = [_]u32{0} ** 8;
            var signal_semaphores: [8][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 8;
            var i: u32 = 0;
            while (i < submit_count) : (i += 1) {
                const info = submits_addr + @as(u64, i) * @sizeOf(abi.SubmitInfo);
                if (state.read64(info + 8) != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
                const wait_count = @min(state.read32(info + 16), 16);
                const wait_address = state.read64(info + 24);
                const stage_address = state.read64(info + 32);
                const command_count = @min(state.read32(info + 40), 256);
                const command_address = state.read64(info + 48);
                const signal_count = @min(state.read32(info + 56), 16);
                const signal_address = state.read64(info + 64);
                if ((wait_count != 0 and (wait_address == 0 or stage_address == 0)) or (command_count != 0 and command_address == 0) or (signal_count != 0 and signal_address == 0)) {
                    return self.refuseVulkanCall(
                        "vkQueueSubmit",
                        "a submit batch has a non-zero count with a null array",
                        abi.ERROR_INITIALIZATION_FAILED,
                        .{ wait_address, command_address, signal_address },
                    );
                }
                for (0..wait_count) |index| {
                    const synthetic = state.read64(wait_address + @as(u64, @intCast(index)) * 8);
                    wait_semaphores[i][index] = self.real_vulkan.realSemaphore(synthetic) orelse
                        return self.refuseVulkanCall(
                            "vkQueueSubmit",
                            "a wait semaphore is not one Rosetta issued",
                            abi.ERROR_INITIALIZATION_FAILED,
                            .{ synthetic, i, index },
                        );
                    wait_stages[i][index] = state.read32(stage_address + @as(u64, @intCast(index)) * 4);
                }
                for (0..command_count) |index| {
                    const synthetic = state.read64(command_address + @as(u64, @intCast(index)) * 8);
                    if (self.fsi_raster.command(synthetic)) |command| {
                        if (command.failed) return self.refuseVulkanCall("vkQueueSubmit", "an FSI sample-count transition invalidated this recording", abi.ERROR_INITIALIZATION_FAILED, .{ synthetic, i, index });
                    }
                    if (self.fsi_raster.moltenvk and self.fsi_raster.allocation_failed) return vkErrorOutOfHostMemory();
                    command_synthetics[i][index] = synthetic;
                    command_buffers[i][index] = self.real_vulkan.realCommandBuffer(synthetic) orelse
                        return self.refuseVulkanCall(
                            "vkQueueSubmit",
                            "a command buffer is not one Rosetta issued",
                            abi.ERROR_INITIALIZATION_FAILED,
                            .{ synthetic, i, index },
                        );
                }
                for (0..signal_count) |index| {
                    const synthetic = state.read64(signal_address + @as(u64, @intCast(index)) * 8);
                    signal_semaphores[i][index] = self.real_vulkan.realSemaphore(synthetic) orelse
                        return self.refuseVulkanCall(
                            "vkQueueSubmit",
                            "a signal semaphore is not one Rosetta issued",
                            abi.ERROR_INITIALIZATION_FAILED,
                            .{ synthetic, i, index },
                        );
                }
                real_submits[i] = .{
                    .wait_semaphore_count = wait_count,
                    .wait_semaphores = if (wait_count == 0) null else &wait_semaphores[i],
                    .wait_dst_stage_mask = if (wait_count == 0) null else &wait_stages[i],
                    .command_buffer_count = command_count,
                    .command_buffers = if (command_count == 0) null else &command_buffers[i],
                    .signal_semaphore_count = signal_count,
                    .signal_semaphores = if (signal_count == 0) null else &signal_semaphores[i],
                };
                command_counts[i] = command_count;
            }
            const fence_real = if (fence_synthetic == 0) 0 else self.real_vulkan.realFence(fence_synthetic) orelse
                return self.refuseVulkanCall(
                    "vkQueueSubmit",
                    "fence handle is not one Rosetta issued",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ fence_synthetic, submit_count, 0 },
                );
            const submit_started = transport_timing.nowNs();
            // FSI work goes out in bounded chunks, each its own Metal
            // command buffer, and is timed (`gpu/vulkan/fsi`).
            const result = if (self.fsiSubmitNeedsExpansion(&command_synthetics, &command_counts, submit_count))
                self.fsiSubmitExpanded(real_queue, submit_fn, &real_submits, &command_synthetics, &command_counts, submit_count, fence_real, state)
            else
                submit_fn(real_queue, submit_count, &real_submits, fence_real);
            self.transport_cost.finish(.queue_submit, submit_started);
            self.noteRealVulkanResult(result, "vkQueueSubmit");
            if (result != abi.SUCCESS) {
                machoCapturePrint("macho-processor: REAL vkQueueSubmit FAILED: VkResult={d} count={d}\n", .{ result, submit_count });
                return @as(u32, @bitCast(result));
            }
            self.vulkan_fence_watch.noteSubmission(fence_synthetic);
            for (0..@as(usize, @intCast(submit_count))) |batch| {
                for (0..@as(usize, @intCast(command_counts[batch]))) |index| {
                    const command_buffer = command_synthetics[batch][index];
                    self.noteFsiSubmittedCommandBuffer(command_buffer, self.vulkan_real_queue_submits + 1, @intCast(batch));
                    self.noteSubmittedCommandTargets(command_buffer);
                }
            }
            self.frame_provenance.noteNativeSubmission();
            self.gpu_runtime.observeBackendProgress(true, false);
            self.vulkan_tiers.note(.queue_submission, .real);
            self.vulkan_real_queue_submits +|= 1;
            if (self.vulkan_queue_submits <= 4) machoCapturePrint("macho-processor: REAL vkQueueSubmit: count={d} fence=0x{x} result=SUCCESS\n", .{ submit_count, fence_synthetic });
            return 0;
        }
    }
    if (self.vulkan_queue_submits == 1) {
        machoCapturePrint(
            "macho-processor: Vulkan milestone: first_queue_submit. real_device={} real_queue={s}\n",
            .{ self.real_vulkan.hasDevice(), if (self.real_vulkan.graphics_queue != null) "YES" else "NO" },
        );
    }
    return 0;
}

pub fn queueSubmit2(self: anytype, state: anytype) u64 {
    if (self.native_texture_state) |native| {
        if (native.terminal_result != abi.SUCCESS) self.noteRealVulkanResult(native.terminal_result, "native Metal texture resources");
    }
    self.vulkan_queue_submits +|= 1;
    self.frame_provenance.noteGuestVulkanCall();
    if (self.realDeviceLostResult()) |result| return result;
    const submit = self.real_vulkan.fn_ptrs.queue_submit2 orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const queue = self.real_vulkan.realQueue(guest_context.registers(state).rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    defer queue_lease.release();
    const requested_count: u32 = @truncate(guest_context.registers(state).rsi);
    // The same fence-only submission the 1.0 path handles, spelled in the
    // synchronization2 form. Returning SUCCESS without forwarding it is
    // the worse of the two failures: the guest is told its fence was
    // submitted and then waits on a fence nothing will ever signal.
    if (requested_count == 0) {
        const fence_only = if (guest_context.registers(state).rcx == 0)
            0
        else
            self.real_vulkan.realFence(guest_context.registers(state).rcx) orelse
                return self.refuseVulkanCall(
                    "vkQueueSubmit2",
                    "fence handle is not one Rosetta issued",
                    abi.ERROR_INITIALIZATION_FAILED,
                    .{ guest_context.registers(state).rcx, 0, 0 },
                );
        if (fence_only == 0) return abi.SUCCESS;
        const empty_result = submit(queue, 0, null, fence_only);
        self.noteRealVulkanResult(empty_result, "vkQueueSubmit2");
        if (empty_result != abi.SUCCESS) return @as(u32, @bitCast(empty_result));
        self.vulkan_fence_only_queue_submits +|= 1;
        self.frame_provenance.noteNativeSubmission();
        self.vulkan_tiers.note(.queue_submission, .real);
        self.vulkan_real_queue_submits +|= 1;
        return 0;
    }
    if (requested_count > 8) {
        return self.refuseVulkanCall(
            "vkQueueSubmit2",
            "submitCount exceeds the batch translation capacity of 8",
            abi.ERROR_INITIALIZATION_FAILED,
            .{ requested_count, 8, guest_context.registers(state).rcx },
        );
    }
    const count: u32 = requested_count;
    const address = guest_context.registers(state).rdx;
    if (address == 0) {
        return self.refuseVulkanCall(
            "vkQueueSubmit2",
            "pSubmits is null with a non-zero submitCount",
            abi.ERROR_INITIALIZATION_FAILED,
            .{ requested_count, 0, guest_context.registers(state).rcx },
        );
    }
    if (state.guestMemoryConst(address, @as(u64, count) * @sizeOf(abi.SubmitInfo2)) == null) return vkErrorInitializationFailed();
    if (!self.uploadMappedMemoryBeforeSubmit(state)) return vkErrorInitializationFailed();
    var submits: [8]abi.SubmitInfo2 = [_]abi.SubmitInfo2{.{}} ** 8;
    var waits: [8][32]abi.SemaphoreSubmitInfo = [_][32]abi.SemaphoreSubmitInfo{[_]abi.SemaphoreSubmitInfo{.{}} ** 32} ** 8;
    var commands: [8][64]abi.CommandBufferSubmitInfo = [_][64]abi.CommandBufferSubmitInfo{[_]abi.CommandBufferSubmitInfo{.{}} ** 64} ** 8;
    var command_synthetics: [8][64]u64 = [_][64]u64{[_]u64{0} ** 64} ** 8;
    var command_counts: [8]u32 = [_]u32{0} ** 8;
    var signals: [8][32]abi.SemaphoreSubmitInfo = [_][32]abi.SemaphoreSubmitInfo{[_]abi.SemaphoreSubmitInfo{.{}} ** 32} ** 8;
    for (0..count) |index| {
        if (!copyGuestValue(abi.SubmitInfo2, state, address + @as(u64, @intCast(index)) * @sizeOf(abi.SubmitInfo2), &submits[index])) return vkErrorInitializationFailed();
        if (submits[index].p_next != null or submits[index].flags != 0) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        if (submits[index].wait_semaphore_info_count > waits[index].len or
            submits[index].command_buffer_info_count > commands[index].len or
            submits[index].signal_semaphore_info_count > signals[index].len) return vkErrorInitializationFailed();
        const wait_address = if (submits[index].wait_semaphore_infos) |pointer| @intFromPtr(pointer) else 0;
        const command_address = if (submits[index].command_buffer_infos) |pointer| @intFromPtr(pointer) else 0;
        const signal_address = if (submits[index].signal_semaphore_infos) |pointer| @intFromPtr(pointer) else 0;
        if ((submits[index].wait_semaphore_info_count != 0 and wait_address == 0) or
            (submits[index].command_buffer_info_count != 0 and command_address == 0) or
            (submits[index].signal_semaphore_info_count != 0 and signal_address == 0)) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.SemaphoreSubmitInfo, state, wait_address, submits[index].wait_semaphore_info_count, &waits[index])) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.CommandBufferSubmitInfo, state, command_address, submits[index].command_buffer_info_count, &commands[index])) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.SemaphoreSubmitInfo, state, signal_address, submits[index].signal_semaphore_info_count, &signals[index])) return vkErrorInitializationFailed();
        for (waits[index][0..@as(usize, @intCast(submits[index].wait_semaphore_info_count))]) |*info| {
            if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
        }
        for (commands[index][0..@as(usize, @intCast(submits[index].command_buffer_info_count))]) |*info| {
            if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            if (self.fsi_raster.command(@intFromPtr(info.command_buffer))) |command| {
                if (command.failed) return vkErrorInitializationFailed();
            }
            if (self.fsi_raster.moltenvk and self.fsi_raster.allocation_failed) return vkErrorOutOfHostMemory();
            command_synthetics[index][command_counts[index]] = @intFromPtr(info.command_buffer);
            command_counts[index] += 1;
            info.command_buffer = self.real_vulkan.realCommandBuffer(@intFromPtr(info.command_buffer)) orelse return vkErrorInitializationFailed();
        }
        for (signals[index][0..@as(usize, @intCast(submits[index].signal_semaphore_info_count))]) |*info| {
            if (info.p_next != null) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            info.semaphore = self.real_vulkan.realSemaphore(info.semaphore) orelse return vkErrorInitializationFailed();
        }
        submits[index].wait_semaphore_infos = if (submits[index].wait_semaphore_info_count == 0) null else &waits[index];
        submits[index].command_buffer_infos = if (submits[index].command_buffer_info_count == 0) null else &commands[index];
        submits[index].signal_semaphore_infos = if (submits[index].signal_semaphore_info_count == 0) null else &signals[index];
    }
    const fence = if (guest_context.registers(state).rcx == 0) 0 else self.real_vulkan.realFence(guest_context.registers(state).rcx) orelse return vkErrorInitializationFailed();
    const submit_started = transport_timing.nowNs();
    const result = submit(queue, count, &submits, fence);
    self.transport_cost.finish(.queue_submit, submit_started);
    self.noteRealVulkanResult(result, "vkQueueSubmit2");
    if (result == abi.SUCCESS) {
        for (0..@as(usize, @intCast(count))) |batch| {
            for (0..@as(usize, @intCast(command_counts[batch]))) |index| {
                const command_buffer = command_synthetics[batch][index];
                self.noteFsiSubmittedCommandBuffer(command_buffer, self.vulkan_real_queue_submits + 1, @intCast(batch));
                self.noteSubmittedCommandTargets(command_buffer);
            }
        }
        self.frame_provenance.noteNativeSubmission();
        self.gpu_runtime.observeBackendProgress(true, false);
        self.vulkan_tiers.note(.queue_submission, .real);
        self.vulkan_real_queue_submits +|= 1;
    }
    return @as(u32, @bitCast(result));
}

pub fn queueBindSparse(self: anytype, state: anytype) u64 {
    if (self.realDeviceLostResult()) |result| return result;
    const bind_sparse = self.real_vulkan.fn_ptrs.queue_bind_sparse orelse return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
    const queue = self.real_vulkan.realQueue(guest_context.registers(state).rdi) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    const count: u32 = @min(@as(u32, @truncate(guest_context.registers(state).rsi)), 4);
    if (count == 0) return abi.SUCCESS;
    var queue_lease = self.lockVulkanQueueApi(state) orelse return @as(u32, @bitCast(abi.ERROR_INITIALIZATION_FAILED));
    defer queue_lease.release();
    const address = guest_context.registers(state).rdx;
    if (address == 0 or state.guestMemoryConst(address, @as(u64, count) * @sizeOf(abi.BindSparseInfo)) == null) return vkErrorInitializationFailed();
    var infos: [4]abi.BindSparseInfo = [_]abi.BindSparseInfo{.{}} ** 4;
    var waits: [4][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 4;
    var signals: [4][16]abi.Semaphore = [_][16]abi.Semaphore{[_]abi.Semaphore{0} ** 16} ** 4;
    var buffer_infos: [4][16]abi.SparseBufferMemoryBindInfo = [_][16]abi.SparseBufferMemoryBindInfo{[_]abi.SparseBufferMemoryBindInfo{.{}} ** 16} ** 4;
    var opaque_infos: [4][16]abi.SparseImageOpaqueMemoryBindInfo = [_][16]abi.SparseImageOpaqueMemoryBindInfo{[_]abi.SparseImageOpaqueMemoryBindInfo{.{}} ** 16} ** 4;
    var image_infos: [4][16]abi.SparseImageMemoryBindInfo = [_][16]abi.SparseImageMemoryBindInfo{[_]abi.SparseImageMemoryBindInfo{.{}} ** 16} ** 4;
    var buffer_binds: [4][16][16]abi.SparseMemoryBind = [_][16][16]abi.SparseMemoryBind{[_][16]abi.SparseMemoryBind{[_]abi.SparseMemoryBind{.{}} ** 16} ** 16} ** 4;
    var opaque_binds: [4][16][16]abi.SparseMemoryBind = [_][16][16]abi.SparseMemoryBind{[_][16]abi.SparseMemoryBind{[_]abi.SparseMemoryBind{.{}} ** 16} ** 16} ** 4;
    var image_binds: [4][16][16]abi.SparseImageMemoryBind = [_][16][16]abi.SparseImageMemoryBind{[_][16]abi.SparseImageMemoryBind{[_]abi.SparseImageMemoryBind{.{}} ** 16} ** 16} ** 4;
    for (0..count) |index| {
        if (!copyGuestValue(abi.BindSparseInfo, state, address + @as(u64, @intCast(index)) * @sizeOf(abi.BindSparseInfo), &infos[index])) return vkErrorInitializationFailed();
        if (infos[index].p_next != null or infos[index].wait_semaphore_count > waits[index].len or infos[index].signal_semaphore_count > signals[index].len or
            infos[index].buffer_bind_count > buffer_infos[index].len or infos[index].image_opaque_bind_count > opaque_infos[index].len or
            infos[index].image_bind_count > image_infos[index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
        const wait_address = if (infos[index].wait_semaphores) |pointer| @intFromPtr(pointer) else 0;
        const signal_address = if (infos[index].signal_semaphores) |pointer| @intFromPtr(pointer) else 0;
        if (!copyGuestStructs(abi.Semaphore, state, wait_address, infos[index].wait_semaphore_count, &waits[index])) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.Semaphore, state, signal_address, infos[index].signal_semaphore_count, &signals[index])) return vkErrorInitializationFailed();
        for (waits[index][0..@as(usize, @intCast(infos[index].wait_semaphore_count))]) |*semaphore| semaphore.* = self.real_vulkan.realSemaphore(semaphore.*) orelse return vkErrorInitializationFailed();
        for (signals[index][0..@as(usize, @intCast(infos[index].signal_semaphore_count))]) |*semaphore| semaphore.* = self.real_vulkan.realSemaphore(semaphore.*) orelse return vkErrorInitializationFailed();
        const buffer_info_address = if (infos[index].buffer_binds) |pointer| @intFromPtr(pointer) else 0;
        const opaque_info_address = if (infos[index].image_opaque_binds) |pointer| @intFromPtr(pointer) else 0;
        const image_info_address = if (infos[index].image_binds) |pointer| @intFromPtr(pointer) else 0;
        if (!copyGuestStructs(abi.SparseBufferMemoryBindInfo, state, buffer_info_address, infos[index].buffer_bind_count, &buffer_infos[index])) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.SparseImageOpaqueMemoryBindInfo, state, opaque_info_address, infos[index].image_opaque_bind_count, &opaque_infos[index])) return vkErrorInitializationFailed();
        if (!copyGuestStructs(abi.SparseImageMemoryBindInfo, state, image_info_address, infos[index].image_bind_count, &image_infos[index])) return vkErrorInitializationFailed();
        for (buffer_infos[index][0..@as(usize, @intCast(infos[index].buffer_bind_count))], 0..) |*bind_info, bind_index| {
            if (bind_info.bind_count > buffer_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.SparseMemoryBind, state, bind_address, bind_info.bind_count, &buffer_binds[index][bind_index])) return vkErrorInitializationFailed();
            bind_info.buffer = self.real_vulkan.realBuffer(bind_info.buffer) orelse return vkErrorInitializationFailed();
            for (buffer_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
            }
            bind_info.binds = if (bind_info.bind_count == 0) null else &buffer_binds[index][bind_index];
        }
        for (opaque_infos[index][0..@as(usize, @intCast(infos[index].image_opaque_bind_count))], 0..) |*bind_info, bind_index| {
            if (bind_info.bind_count > opaque_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.SparseMemoryBind, state, bind_address, bind_info.bind_count, &opaque_binds[index][bind_index])) return vkErrorInitializationFailed();
            bind_info.image = self.real_vulkan.realImage(bind_info.image) orelse return vkErrorInitializationFailed();
            for (opaque_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
            }
            bind_info.binds = if (bind_info.bind_count == 0) null else &opaque_binds[index][bind_index];
        }
        for (image_infos[index][0..@as(usize, @intCast(infos[index].image_bind_count))], 0..) |*bind_info, bind_index| {
            if (bind_info.bind_count > image_binds[index][bind_index].len) return @as(u32, @bitCast(abi.ERROR_FEATURE_NOT_PRESENT));
            const bind_address = if (bind_info.binds) |pointer| @intFromPtr(pointer) else 0;
            if (!copyGuestStructs(abi.SparseImageMemoryBind, state, bind_address, bind_info.bind_count, &image_binds[index][bind_index])) return vkErrorInitializationFailed();
            bind_info.image = self.real_vulkan.realImage(bind_info.image) orelse return vkErrorInitializationFailed();
            for (image_binds[index][bind_index][0..@as(usize, @intCast(bind_info.bind_count))]) |*bind| {
                if (bind.memory != 0) bind.memory = self.real_vulkan.realMemory(bind.memory) orelse return vkErrorInitializationFailed();
            }
            bind_info.binds = if (bind_info.bind_count == 0) null else &image_binds[index][bind_index];
        }
        infos[index].wait_semaphores = if (infos[index].wait_semaphore_count == 0) null else &waits[index];
        infos[index].signal_semaphores = if (infos[index].signal_semaphore_count == 0) null else &signals[index];
        infos[index].buffer_binds = if (infos[index].buffer_bind_count == 0) null else &buffer_infos[index];
        infos[index].image_opaque_binds = if (infos[index].image_opaque_bind_count == 0) null else &opaque_infos[index];
        infos[index].image_binds = if (infos[index].image_bind_count == 0) null else &image_infos[index];
    }
    const fence = if (guest_context.registers(state).rcx == 0) 0 else self.real_vulkan.realFence(guest_context.registers(state).rcx) orelse return vkErrorInitializationFailed();
    const result = bind_sparse(queue, count, &infos, fence);
    self.noteRealVulkanResult(result, "vkQueueBindSparse");
    return @as(u32, @bitCast(result));
}
