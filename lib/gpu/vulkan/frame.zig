//! Which frame owns which swapchain image, and when the swapchain is no longer
//! usable.
//!
//! Two bugs live in this bookkeeping and neither announces itself. The first is
//! reusing a per-frame semaphore or command buffer while the previous
//! submission that used it is still executing — legal-looking code, correct
//! output most of the time, corruption under load. The second is presenting
//! against a swapchain the surface has already outgrown, which returns success
//! for a while and then never recovers.
//!
//! Both are state-machine problems, not Vulkan problems, so they are separated
//! from the driver calls and decided here. The rule the ring enforces is that a
//! frame slot may not be reused until its fence has been waited on, and an
//! image may not be written by a new frame until the frame that last wrote it
//! has completed — which is a different constraint, because the number of
//! images and the number of in-flight frames are not the same number.
//!
//! `Health` exists because "the swapchain needs rebuilding" and "the device is
//! gone" demand opposite responses, and a runtime that answers device loss by
//! rebuilding the swapchain rebuilds it on a dead device, forever.

const std = @import("std");
const selection = @import("selection.zig");

pub const max_frames_in_flight: u32 = 3;
pub const max_swapchain_images: u32 = 8;

/// Whether the swapchain can still be used, and what has to happen if not.
pub const Health = enum(u8) {
    /// Usable.
    ready,
    /// Still usable this frame, but must be rebuilt before the next.
    stale,
    /// Not usable. Rebuild the swapchain against the current surface.
    out_of_date,
    /// Not usable. Rebuild the surface as well as the swapchain.
    surface_lost,
    /// Terminal for this session. Nothing on this device may be used again,
    /// including to tear itself down.
    device_lost,

    pub fn canAcquire(self: Health) bool {
        return self == .ready or self == .stale;
    }

    /// Whether rebuilding the swapchain is the correct response. Device loss is
    /// deliberately excluded: rebuilding there loops forever on a dead device.
    pub fn wantsSwapchainRebuild(self: Health) bool {
        return self == .stale or self == .out_of_date or self == .surface_lost;
    }

    pub fn label(self: Health) []const u8 {
        return switch (self) {
            .ready => "ready",
            .stale => "stale (usable once, rebuild before the next frame)",
            .out_of_date => "out of date (rebuild the swapchain)",
            .surface_lost => "surface lost (rebuild the surface and the swapchain)",
            .device_lost => "device lost (the session is over)",
        };
    }
};

/// Health only ever gets worse within a swapchain generation. Taking the more
/// severe of the two stops a later `VK_SUCCESS` from erasing an earlier
/// out-of-date, which would leave the presenter looping on a swapchain it had
/// already been told to rebuild.
pub fn worse(current: Health, observed: Health) Health {
    return if (@intFromEnum(observed) > @intFromEnum(current)) observed else current;
}

pub fn healthAfterAcquire(outcome: selection.AcquireOutcome) Health {
    return switch (outcome) {
        .acquired, .retry => .ready,
        .acquired_suboptimal => .stale,
        .recreate => .out_of_date,
        .surface_lost => .surface_lost,
        .device_lost => .device_lost,
        .failed => .out_of_date,
    };
}

pub fn healthAfterPresent(outcome: selection.PresentOutcome) Health {
    return switch (outcome) {
        .presented => .ready,
        .presented_suboptimal => .stale,
        .recreate => .out_of_date,
        .surface_lost => .surface_lost,
        .device_lost => .device_lost,
        .failed => .out_of_date,
    };
}

pub const Ring = struct {
    frames_in_flight: u32 = 2,
    image_count: u32 = 0,
    current_frame: u32 = 0,
    /// Incremented on every swapchain rebuild. A frame carrying an older
    /// generation is describing images that no longer exist.
    generation: u32 = 0,
    health: Health = .ready,
    /// Which frame slot last submitted work touching each image, or `null` if
    /// the image is free. Not the same as the frame slot ring: an image may sit
    /// in flight across several frame slots.
    image_owner: [max_swapchain_images]?u32 = [_]?u32{null} ** max_swapchain_images,
    frames_started: u64 = 0,
    frames_completed: u64 = 0,
    /// Times a frame had to wait on an image still owned by an earlier frame.
    /// A persistently high value means the swapchain has too few images for the
    /// number of frames in flight.
    image_contention: u64 = 0,

    pub fn configure(self: *Ring, image_count: u32, frames_in_flight: u32) void {
        self.image_count = @min(image_count, max_swapchain_images);
        self.frames_in_flight = std.math.clamp(frames_in_flight, 1, max_frames_in_flight);
        // Never keep more frames in flight than there are images to write.
        if (self.image_count != 0) self.frames_in_flight = @min(self.frames_in_flight, self.image_count);
        self.current_frame = 0;
        self.image_owner = [_]?u32{null} ** max_swapchain_images;
    }

    /// A new swapchain invalidates every image and every ownership record, but
    /// not the frame slots: their fences and semaphores outlive the swapchain
    /// and must still be waited on before reuse.
    pub fn recreated(self: *Ring, image_count: u32) void {
        const frames = self.frames_in_flight;
        self.configure(image_count, frames);
        self.generation +%= 1;
        self.health = .ready;
    }

    pub fn note(self: *Ring, observed: Health) void {
        self.health = worse(self.health, observed);
    }

    /// Clears a `stale` back to `ready` once the rebuild has happened. Anything
    /// worse than stale is not cleared here, because it needs a rebuild this
    /// function is not performing.
    pub fn clearStale(self: *Ring) void {
        if (self.health == .stale) self.health = .ready;
    }

    pub fn beginFrame(self: *Ring) u32 {
        self.frames_started +|= 1;
        return self.current_frame;
    }

    /// Take ownership of an image for the current frame. Returns the frame slot
    /// that last wrote it and whose completion must be awaited first, or `null`
    /// when the image is free.
    pub fn claimImage(self: *Ring, image_index: u32) ?u32 {
        if (image_index >= self.image_count) return null;
        const previous = self.image_owner[image_index];
        if (previous) |slot| {
            if (slot != self.current_frame) self.image_contention +|= 1;
        }
        self.image_owner[image_index] = self.current_frame;
        return previous;
    }

    /// Release every image a completed frame slot still owns.
    pub fn completeFrame(self: *Ring, slot: u32) void {
        for (self.image_owner[0..@min(self.image_count, max_swapchain_images)]) |*owner| {
            if (owner.* == slot) owner.* = null;
        }
        self.frames_completed +|= 1;
    }

    pub fn advance(self: *Ring) void {
        if (self.frames_in_flight == 0) return;
        self.current_frame = (self.current_frame + 1) % self.frames_in_flight;
    }

    pub fn inFlight(self: *const Ring) u64 {
        return self.frames_started - self.frames_completed;
    }
};

test "an unrecoverable state is never overwritten by a later success" {
    var ring = Ring{};
    ring.configure(3, 2);
    ring.note(.out_of_date);
    ring.note(.ready);
    try std.testing.expectEqual(Health.out_of_date, ring.health);
    try std.testing.expect(!ring.health.canAcquire());
}

// Device loss and out-of-date look similar in a log and demand opposite
// responses. Rebuilding on a lost device is an infinite loop that reports
// progress every iteration.
test "device loss does not ask for a swapchain rebuild" {
    try std.testing.expect(Health.out_of_date.wantsSwapchainRebuild());
    try std.testing.expect(Health.surface_lost.wantsSwapchainRebuild());
    try std.testing.expect(!Health.device_lost.wantsSwapchainRebuild());
    try std.testing.expect(!Health.device_lost.canAcquire());
}

// Suboptimal is usable now and stale afterwards; dropping the frame wastes it
// and keeping the swapchain leaves a permanent mismatch.
test "a suboptimal acquire leaves the swapchain usable but marked stale" {
    const health = healthAfterAcquire(.acquired_suboptimal);
    try std.testing.expectEqual(Health.stale, health);
    try std.testing.expect(health.canAcquire());
    try std.testing.expect(health.wantsSwapchainRebuild());
}

test "a timed-out acquire leaves the swapchain healthy" {
    try std.testing.expectEqual(Health.ready, healthAfterAcquire(.retry));
    try std.testing.expectEqual(Health.out_of_date, healthAfterAcquire(.recreate));
    try std.testing.expectEqual(Health.device_lost, healthAfterPresent(.device_lost));
}

// The invariant the whole file exists for: a second frame must not write an
// image the first frame's submission has not finished with.
test "an image still owned by an earlier frame reports the slot to wait on" {
    var ring = Ring{};
    ring.configure(2, 2);

    const first = ring.beginFrame();
    try std.testing.expect(ring.claimImage(0) == null);
    ring.advance();

    const second = ring.beginFrame();
    try std.testing.expect(first != second);
    // The presentation engine handed back image 0 again while frame 0 is still
    // in flight.
    try std.testing.expectEqual(first, ring.claimImage(0).?);
    try std.testing.expectEqual(@as(u64, 1), ring.image_contention);
}

test "completing a frame releases the images it held" {
    var ring = Ring{};
    ring.configure(3, 2);
    const slot = ring.beginFrame();
    _ = ring.claimImage(1);
    ring.completeFrame(slot);
    try std.testing.expect(ring.claimImage(1) == null);
    try std.testing.expectEqual(@as(u64, 1), ring.frames_completed);
    try std.testing.expectEqual(@as(u64, 0), ring.inFlight());
}

// A swapchain with fewer images than the requested frames in flight would let
// two frames target the same image with nothing between them.
test "frames in flight never exceed the number of swapchain images" {
    var ring = Ring{};
    ring.configure(1, 3);
    try std.testing.expectEqual(@as(u32, 1), ring.frames_in_flight);
    ring.advance();
    try std.testing.expectEqual(@as(u32, 0), ring.current_frame);
}

test "recreation invalidates ownership and advances the generation" {
    var ring = Ring{};
    ring.configure(2, 2);
    _ = ring.beginFrame();
    _ = ring.claimImage(0);
    ring.note(.out_of_date);

    ring.recreated(3);
    try std.testing.expectEqual(@as(u32, 1), ring.generation);
    try std.testing.expectEqual(@as(u32, 3), ring.image_count);
    try std.testing.expectEqual(Health.ready, ring.health);
    try std.testing.expect(ring.claimImage(0) == null);
}

test "clearing stale does not clear anything more serious" {
    var ring = Ring{};
    ring.configure(2, 2);
    ring.note(.stale);
    ring.clearStale();
    try std.testing.expectEqual(Health.ready, ring.health);

    ring.note(.surface_lost);
    ring.clearStale();
    try std.testing.expectEqual(Health.surface_lost, ring.health);
}

test "every health state explains what it requires" {
    inline for (@typeInfo(Health).@"enum".fields) |field| {
        const health: Health = @enumFromInt(field.value);
        try std.testing.expect(health.label().len > 0);
    }
}
