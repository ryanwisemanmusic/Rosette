//! How much of the graphics path reaches real hardware.
//!
//! Bringing a window up is not the same as rendering into it. A runtime can
//! reach a genuine `NSWindow` → `CAMetalLayer` → `VkSurfaceKHR` and still be
//! answering every subsequent Vulkan call itself — returning plausible handles,
//! accepting command buffers, reporting successful presents — while nothing the
//! guest drew ever reaches the display. The window is real, the frame in it is
//! the runtime's own, and no counter distinguishes the two.
//!
//! That distinction is what this owns. Each stage of the path is declared either
//! **native** (forwarded to the host driver) or **modelled** (answered by the
//! runtime), and the contract states the one consequence that follows: pixels
//! are authoritative only when every stage a frame passes through is native.
//!
//! Written down as a contract rather than tracked as a flag because the honest
//! answer changes per stage and per run, and because "the swapchain is
//! synthetic" is a fact a reader needs *before* interpreting a screenshot — not
//! after concluding the renderer is broken.
//!
//! Two things it deliberately does not do. It does not implement forwarding:
//! that is the driver bridge's job, and this is what tells you how much of it
//! exists. And it never reports a modelled stage as native to make a summary
//! look better — a runtime that overstates its own fidelity is worse than one
//! that renders nothing, because the second is obvious.

const std = @import("std");

/// One stage a frame must pass through. Ordered from instance creation to
/// presentation, which is also dependency order: a native stage below a
/// modelled one cannot make the frame authoritative.
pub const Stage = enum(u8) {
    instance,
    surface,
    physical_device,
    logical_device,
    queue,
    swapchain,
    swapchain_images,
    command_recording,
    queue_submission,
    presentation,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .instance => "VkInstance",
            .surface => "VkSurfaceKHR",
            .physical_device => "VkPhysicalDevice",
            .logical_device => "VkDevice",
            .queue => "VkQueue",
            .swapchain => "VkSwapchainKHR",
            .swapchain_images => "swapchain VkImages",
            .command_recording => "command buffer recording",
            .queue_submission => "vkQueueSubmit",
            .presentation => "vkQueuePresentKHR",
        };
    }

    /// Whether a frame's pixels pass through this stage. Stages that only
    /// establish context (instance, surface) are required for the path to exist
    /// but do not themselves carry pixel data, so a modelled one of those is a
    /// different, lesser problem than a modelled submission.
    pub fn carriesPixels(self: Stage) bool {
        return switch (self) {
            .instance, .surface, .physical_device => false,
            .logical_device,
            .queue,
            .swapchain,
            .swapchain_images,
            .command_recording,
            .queue_submission,
            .presentation,
            => true,
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

pub const Fidelity = enum(u8) {
    /// Not reached yet. Distinct from modelled: an unreached stage says nothing
    /// about what the runtime would do there.
    unreached,
    /// Answered by the runtime. Calls succeed and the objects are plausible;
    /// the host driver never saw them.
    modelled,
    /// Forwarded to the host driver.
    native,
};

pub const Contract = struct {
    fidelity: [stage_count]Fidelity = [_]Fidelity{.unreached} ** stage_count,

    pub fn declare(self: *Contract, stage: Stage, fidelity: Fidelity) void {
        self.fidelity[@intFromEnum(stage)] = fidelity;
    }

    pub fn of(self: *const Contract, stage: Stage) Fidelity {
        return self.fidelity[@intFromEnum(stage)];
    }

    /// The first pixel-carrying stage that is not native — the reason a frame is
    /// not the guest's, and the next thing to build.
    pub fn firstNonNativePixelStage(self: *const Contract) ?Stage {
        inline for (@typeInfo(Stage).@"enum".fields) |field| {
            const stage: Stage = @enumFromInt(field.value);
            if (stage.carriesPixels() and self.of(stage) != .native) return stage;
        }
        return null;
    }

    /// Pixels are the guest's only when every stage that carries them is native.
    /// Stated as a single predicate so no caller assembles its own version of
    /// this rule and reaches a friendlier answer.
    pub fn pixelsAreGuestOutput(self: *const Contract) bool {
        return self.firstNonNativePixelStage() == null;
    }

    pub fn count(self: *const Contract, fidelity: Fidelity) usize {
        var total: usize = 0;
        for (self.fidelity) |entry| {
            if (entry == fidelity) total += 1;
        }
        return total;
    }
};

/// What the runtime should say about anything drawn on screen.
pub fn visibilityNote(contract: *const Contract) []const u8 {
    if (contract.pixelsAreGuestOutput()) {
        return "every pixel-carrying stage is forwarded to the host driver, so what is displayed is the guest's output";
    }
    if (contract.of(.surface) == .native) {
        return "the window and surface are real but at least one pixel-carrying stage is answered by the runtime, so what is displayed is DIAGNOSTIC OUTPUT, not the guest's. Do not read it as evidence about the guest's rendering";
    }
    return "the surface itself is not native, so nothing displayed relates to the guest at all";
}

test "an untouched contract has reached nothing and claims nothing" {
    const contract = Contract{};
    try std.testing.expectEqual(Fidelity.unreached, contract.of(.instance));
    try std.testing.expect(!contract.pixelsAreGuestOutput());
    try std.testing.expectEqual(stage_count, contract.count(.unreached));
}

// The observed configuration: a genuine window and surface, everything past it
// answered by the runtime. The window being real is exactly what makes this
// dangerous to read casually.
test "a native surface over modelled stages is diagnostic output, not guest output" {
    var contract = Contract{};
    contract.declare(.instance, .native);
    contract.declare(.surface, .native);
    contract.declare(.physical_device, .modelled);
    contract.declare(.logical_device, .modelled);
    contract.declare(.queue, .modelled);
    contract.declare(.swapchain, .modelled);
    contract.declare(.swapchain_images, .modelled);
    contract.declare(.command_recording, .modelled);
    contract.declare(.queue_submission, .modelled);
    contract.declare(.presentation, .modelled);

    try std.testing.expect(!contract.pixelsAreGuestOutput());
    try std.testing.expectEqual(Stage.logical_device, contract.firstNonNativePixelStage().?);
    try std.testing.expect(std.mem.indexOf(u8, visibilityNote(&contract), "DIAGNOSTIC OUTPUT") != null);
}

// A modelled stage that does not carry pixels is a lesser problem, and
// conflating the two would make the next thing to build unclear.
test "a modelled physical device does not by itself invalidate pixels" {
    var contract = Contract{};
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        contract.declare(@enumFromInt(field.value), .native);
    }
    contract.declare(.physical_device, .modelled);
    try std.testing.expect(contract.pixelsAreGuestOutput());
    try std.testing.expect(std.mem.indexOf(u8, visibilityNote(&contract), "guest's output") != null);
}

test "the first non-native pixel stage is the next thing to build" {
    var contract = Contract{};
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        contract.declare(@enumFromInt(field.value), .native);
    }
    contract.declare(.queue_submission, .modelled);
    try std.testing.expectEqual(Stage.queue_submission, contract.firstNonNativePixelStage().?);
    try std.testing.expect(!contract.pixelsAreGuestOutput());

    contract.declare(.queue_submission, .native);
    try std.testing.expect(contract.pixelsAreGuestOutput());
}

// An unreached stage is not a modelled one: it says nothing about what the
// runtime would do, and reporting it as modelled would invent a finding.
test "unreached is distinct from modelled" {
    var contract = Contract{};
    contract.declare(.instance, .native);
    try std.testing.expectEqual(Fidelity.unreached, contract.of(.presentation));
    try std.testing.expectEqual(@as(usize, 1), contract.count(.native));
    try std.testing.expectEqual(@as(usize, 0), contract.count(.modelled));
    try std.testing.expectEqual(stage_count - 1, contract.count(.unreached));
}

test "a surface that is not native says so plainly" {
    var contract = Contract{};
    contract.declare(.instance, .native);
    contract.declare(.surface, .modelled);
    try std.testing.expect(std.mem.indexOf(u8, visibilityNote(&contract), "not native") != null);
}
