//! What has to be true before a title's display bring-up runs, in what order,
//! and who was supposed to make it true.
//!
//! The graphics contract answers "which precondition is unmet". This answers a
//! different question that no ladder can: **were they established in the right
//! order?** On real hardware the kernel has finished writing platform state
//! before the title's first instruction executes, so ordering is not a property
//! anyone has to think about. Here every piece is established by a different
//! actor at a different moment, and a title that reads a variable one
//! millisecond before the thing that populates it runs sees a zero and takes
//! its early-return path — permanently, because nothing re-reads it.
//!
//! That failure is invisible to a ladder. Every rung eventually shows as
//! reached; the run still never presents. The ladder says "all preconditions
//! met" and the title is wedged on a decision it made before they were.
//!
//! ## Ordering is a first-class finding here
//!
//! Each element declares what must precede it. When an element is observed and
//! its prerequisite has not been, that is recorded as an **inversion** — not as
//! progress, and not as an error either, because the run continues and looks
//! healthy. An inversion is the single most useful thing this module produces:
//! it names a moment where the title could have read something that was not yet
//! there, which is exactly the class of bug that leaves a run submitting
//! commands forever and never presenting.
//!
//! ## Owners decide what a gap means
//!
//! `platform` elements are the harness's to supply — they are what the console's
//! kernel wrote before the title ran, and supplying them is the entire point of
//! a harness. `emulator` elements are observed and never written. `title`
//! elements are the title's decisions, and a gap there is information about the
//! title rather than work for anyone.

const std = @import("std");

pub const Owner = enum {
    /// State the real kernel established before the title ran. The harness may
    /// and should supply it.
    platform,
    /// The emulator establishes it. Observe; never write.
    emulator,
    /// The title decides it. A gap is information, not work.
    title,

    pub fn label(self: Owner) []const u8 {
        return switch (self) {
            .platform => "platform",
            .emulator => "emulator",
            .title => "title",
        };
    }

    pub fn harnessMaySupply(self: Owner) bool {
        return self == .platform;
    }
};

/// Everything that must exist before a title will present, in the order the
/// console establishes it.
pub const Element = enum(u8) {
    /// The harness knows where the emulator mapped console memory. Nothing else
    /// here can be read or written until this is true, which is why it is first
    /// even though it is not console state at all.
    memory_view_base_discovered,
    /// Every kernel variable the title imports has an import slot pointing at
    /// real storage. Not that the storage holds a value — only that the
    /// dereference lands somewhere.
    kernel_variable_slots_bound,
    /// The GPU clock the title reads for timing arithmetic.
    gpu_clock_published,
    /// The HSIO calibration lock is an initialised critical section rather than
    /// a zeroed one.
    hsio_lock_initialised,
    /// The Xenos register aperture is reachable: its pages are mapped and the
    /// emulator has registered a handler for them, so a store that arrives is
    /// dispatched rather than lost. Reachability, not usage — a title that
    /// programs its GPU through kernel exports never stores here, and that says
    /// nothing about whether it could.
    register_aperture_reachable,
    /// `VdInitializeEngines` ran.
    engines_initialised,
    /// The title registered its graphics interrupt callback.
    interrupt_callback_registered,
    /// The emulator dispatched that callback at least once.
    interrupt_callback_dispatched,
    /// `VdInitializeRingBuffer` established a base and size.
    ring_geometry_established,
    /// The emulator's command processor is running and draining.
    command_processor_running,
    /// The title created its Direct3D device and stored the pointer.
    title_device_created,
    /// The title wrote command dwords into the ring.
    ring_payload_written,
    /// The title advanced the ring write pointer.
    write_pointer_advanced,

    pub fn owner(self: Element) Owner {
        return switch (self) {
            .memory_view_base_discovered,
            .kernel_variable_slots_bound,
            .gpu_clock_published,
            .hsio_lock_initialised,
            => .platform,

            .register_aperture_reachable,
            .interrupt_callback_dispatched,
            .command_processor_running,
            => .emulator,

            .engines_initialised,
            .interrupt_callback_registered,
            .ring_geometry_established,
            .title_device_created,
            .ring_payload_written,
            .write_pointer_advanced,
            => .title,
        };
    }

    /// The element that must be established before this one. Null for the
    /// first, and for elements with no ordering relationship worth asserting —
    /// claiming an order that does not exist manufactures inversions.
    pub fn prerequisite(self: Element) ?Element {
        return switch (self) {
            .memory_view_base_discovered => null,
            .kernel_variable_slots_bound => .memory_view_base_discovered,
            .gpu_clock_published => .kernel_variable_slots_bound,
            .hsio_lock_initialised => .kernel_variable_slots_bound,
            .register_aperture_reachable => null,
            // The whole point of the module: a title that initialises engines
            // reads platform state while doing it.
            .engines_initialised => .gpu_clock_published,
            .interrupt_callback_registered => .engines_initialised,
            .interrupt_callback_dispatched => .interrupt_callback_registered,
            .ring_geometry_established => .engines_initialised,
            .command_processor_running => .ring_geometry_established,
            .title_device_created => .engines_initialised,
            .ring_payload_written => .ring_geometry_established,
            .write_pointer_advanced => .ring_payload_written,
        };
    }

    /// Whether this element must exist for a frame.
    ///
    /// Every element is now required, because every element is now defined as
    /// something that can actually be established. The register aperture was
    /// briefly optional for the wrong reason: it was defined as "a guest store
    /// reached the register file", which a title programming its GPU through
    /// kernel exports never does, so it sat ABSENT forever and had to be
    /// excluded from the frontier to stop it accusing the emulator. The element
    /// is really about *reachability* — mapped pages with a registered handler
    /// — which the emulator states directly and which is either true or a
    /// genuine defect. Defined that way it is satisfiable, so it is required.
    pub fn required(self: Element) bool {
        _ = self;
        return true;
    }

    pub fn label(self: Element) []const u8 {
        return switch (self) {
            .memory_view_base_discovered => "console memory view base discovered",
            .kernel_variable_slots_bound => "kernel variable slots bound to storage",
            .gpu_clock_published => "VdGpuClockInMHz published",
            .hsio_lock_initialised => "VdHSIOCalibrationLock initialised",
            .register_aperture_reachable => "Xenos register aperture reachable",
            .engines_initialised => "VdInitializeEngines ran",
            .interrupt_callback_registered => "graphics interrupt callback registered",
            .interrupt_callback_dispatched => "graphics interrupt callback dispatched",
            .ring_geometry_established => "ring buffer geometry established",
            .command_processor_running => "command processor running",
            .title_device_created => "title created its Direct3D device",
            .ring_payload_written => "command dwords written into the ring",
            .write_pointer_advanced => "ring write pointer advanced",
        };
    }

    /// What the title does when this is absent at the moment it looks. Written
    /// as the observable consequence, because "it is missing" is what the state
    /// already says.
    pub fn consequence(self: Element) []const u8 {
        return switch (self) {
            .memory_view_base_discovered => "nothing in console memory can be read or written from here, so every element below this one is unknowable rather than absent",
            .kernel_variable_slots_bound => "a title dereferencing an unbound slot reads through a null or fabricated pointer. On this platform that is a near-null read the title does not check, and the value it gets is whatever the fault path leaves behind",
            .gpu_clock_published => "timing arithmetic that scales by the clock divides by zero or scales to zero. A frame-pacing decision made against it can gate presentation permanently, because nothing re-reads the clock",
            .hsio_lock_initialised => "a critical section whose state word was never written reads as held by a thread that does not exist. A title taking it waits for an owner that will never release",
            .register_aperture_reachable => "the register aperture is not known to be reachable: no handler registration has been observed for it and no access has ever arrived. A store the title makes would be lost rather than dispatched, so any register programming it attempts goes nowhere. This is reachability, not usage — a title can be perfectly healthy and never store here",
            .engines_initialised => "the title has not begun graphics bring-up at all; everything below is a consequence",
            .interrupt_callback_registered => "the title will not be told about vblank, so any present loop driven by it never runs",
            .interrupt_callback_dispatched => "the callback is registered and never fires; a title waiting on it waits forever",
            .ring_geometry_established => "there is nowhere to submit commands",
            .command_processor_running => "commands submitted are never drained",
            .title_device_created => "the title's display layer has not produced a device, so it has not reached the code that would present",
            .ring_payload_written => "the title has produced no command batch",
            .write_pointer_advanced => "a batch exists and was never published",
        };
    }
};

pub const element_count = @typeInfo(Element).@"enum".fields.len;

pub const State = enum {
    /// Never observed.
    absent,
    /// Observed as established by whoever owns it.
    established,
    /// Supplied by the harness. Only reachable for `platform` elements.
    supplied,

    pub fn present(self: State) bool {
        return self != .absent;
    }

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .absent => "ABSENT",
            .established => "established",
            .supplied => "supplied",
        };
    }
};

const Entry = struct {
    state: State = .absent,
    step: u64 = 0,
    observations: u64 = 0,
};

/// An element that became true before the thing it depends on did.
pub const Inversion = struct {
    element: Element,
    prerequisite: Element,
    step: u64,
};

pub const max_inversions = 8;

pub const Ledger = struct {
    entries: [element_count]Entry = [_]Entry{.{}} ** element_count,
    inversions: [max_inversions]Inversion = undefined,
    inversion_count: u32 = 0,
    /// Inversions past the retained window. Counted so the report never claims
    /// a bounded list is the whole story.
    inversions_dropped: u64 = 0,
    /// Attempts to supply an element the harness does not own.
    refused_supplies: u64 = 0,

    fn at(self: *Ledger, element: Element) *Entry {
        return &self.entries[@intFromEnum(element)];
    }

    /// Record that an element is established, and check the ordering.
    ///
    /// Ordering is checked at the moment of establishment rather than at the
    /// end: by the end everything is present and the inversion is invisible,
    /// which is precisely why this class of bug survives a ladder.
    pub fn observe(self: *Ledger, element: Element, step: u64) void {
        const entry = self.at(element);
        entry.observations +|= 1;
        if (entry.state.present()) return;

        if (element.prerequisite()) |required| {
            if (!self.entries[@intFromEnum(required)].state.present()) {
                if (self.inversion_count < max_inversions) {
                    self.inversions[self.inversion_count] = .{
                        .element = element,
                        .prerequisite = required,
                        .step = step,
                    };
                    self.inversion_count += 1;
                } else {
                    self.inversions_dropped +|= 1;
                }
            }
        }
        entry.state = .established;
        entry.step = step;
    }

    /// The harness supplying platform state. Refuses anything it does not own,
    /// by the same rule the graphics contract enforces.
    pub fn supply(self: *Ledger, element: Element, step: u64) bool {
        if (!element.owner().harnessMaySupply()) {
            self.refused_supplies +|= 1;
            return false;
        }
        const entry = self.at(element);
        entry.observations +|= 1;
        if (entry.state.present()) return true;
        entry.state = .supplied;
        entry.step = step;
        return true;
    }

    pub fn state(self: *const Ledger, element: Element) State {
        return self.entries[@intFromEnum(element)].state;
    }

    pub fn establishedCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.entries) |entry| {
            if (entry.state.present()) count += 1;
        }
        return count;
    }

    /// The first *required* element in order that is not established.
    /// Informative elements are reported and never become the frontier.
    pub fn firstGap(self: *const Ledger) ?Element {
        inline for (@typeInfo(Element).@"enum".fields) |field| {
            const element: Element = @enumFromInt(field.value);
            if (element.required() and !self.state(element).present()) return element;
        }
        return null;
    }

    /// Platform elements the harness could supply and has not. The actionable
    /// list: everything here is work that needs no cooperation from the
    /// emulator or the title.
    pub fn outstandingPlatformWork(self: *const Ledger, out: []Element) []Element {
        var count: usize = 0;
        inline for (@typeInfo(Element).@"enum".fields) |field| {
            const element: Element = @enumFromInt(field.value);
            if (count < out.len and element.owner() == .platform and !self.state(element).present()) {
                out[count] = element;
                count += 1;
            }
        }
        return out[0..count];
    }

    /// One sentence naming what this run's pre-initialisation actually was.
    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.inversion_count != 0)
            return "at least one element became true after something that depends on it. The run will look healthy from here — every element is established by the end — but the dependent read happened while the value was still absent, and nothing re-reads it. This is the ordering defect a ladder cannot see, and the first inversion below is where to look";
        if (self.firstGap()) |gap| {
            return switch (gap.owner()) {
                .platform => "the first gap is platform state the harness owns and has not supplied. This needs no cooperation from the emulator or the title",
                .emulator => "the first gap is the emulator's. Observe and report; writing it here would hide the defect",
                .title => "the first gap is the title's own decision. Nothing the harness supplies will move it, and its absence is information about where the title stopped",
            };
        }
        return "every element is established and none of them was established out of order, so pre-initialisation is not what is stopping this run";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "the first gap is the first unestablished element in order" {
    var ledger = Ledger{};
    try std.testing.expectEqual(Element.memory_view_base_discovered, ledger.firstGap().?);

    ledger.observe(.memory_view_base_discovered, 1);
    ledger.observe(.kernel_variable_slots_bound, 2);
    try std.testing.expectEqual(Element.gpu_clock_published, ledger.firstGap().?);
    try std.testing.expectEqual(@as(u32, 2), ledger.establishedCount());
}

// The whole reason the module exists. By the end everything is present, so a
// ladder reports success — and the title read the clock before it was written.
test "an element established after its dependent is recorded as an inversion" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    ledger.observe(.kernel_variable_slots_bound, 2);
    // Engines initialise before the clock is published: the title read it.
    ledger.observe(.engines_initialised, 3);
    ledger.observe(.gpu_clock_published, 4);

    try std.testing.expectEqual(@as(u32, 1), ledger.inversion_count);
    try std.testing.expectEqual(Element.engines_initialised, ledger.inversions[0].element);
    try std.testing.expectEqual(Element.gpu_clock_published, ledger.inversions[0].prerequisite);
    try std.testing.expectEqual(@as(u64, 3), ledger.inversions[0].step);

    // Everything below is established, so no gap remains to point at.
    ledger.observe(.hsio_lock_initialised, 5);
    ledger.observe(.register_aperture_reachable, 6);
    ledger.observe(.interrupt_callback_registered, 7);
    ledger.observe(.interrupt_callback_dispatched, 8);
    ledger.observe(.ring_geometry_established, 9);
    ledger.observe(.command_processor_running, 10);
    ledger.observe(.title_device_created, 11);
    ledger.observe(.ring_payload_written, 12);
    ledger.observe(.write_pointer_advanced, 13);
    try std.testing.expect(ledger.firstGap() == null);
    // And the verdict still names the ordering rather than reporting success.
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "ordering defect a ladder cannot see") != null);
}

test "an element established in order produces no inversion" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    ledger.observe(.kernel_variable_slots_bound, 2);
    ledger.observe(.gpu_clock_published, 3);
    ledger.observe(.engines_initialised, 4);
    try std.testing.expectEqual(@as(u32, 0), ledger.inversion_count);
}

test "the harness may supply platform state and nothing else" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.supply(.gpu_clock_published, 10));
    try std.testing.expectEqual(State.supplied, ledger.state(.gpu_clock_published));

    // A title's decision is never suppliable, and the attempt is counted.
    try std.testing.expect(!ledger.supply(.ring_payload_written, 11));
    try std.testing.expectEqual(State.absent, ledger.state(.ring_payload_written));
    try std.testing.expectEqual(@as(u64, 1), ledger.refused_supplies);

    // Nor the emulator's, for the same reason: writing it hides the defect.
    try std.testing.expect(!ledger.supply(.command_processor_running, 12));
    try std.testing.expectEqual(@as(u64, 2), ledger.refused_supplies);
}

test "supplied state counts as present but stays distinguishable from established" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    _ = ledger.supply(.kernel_variable_slots_bound, 2);
    _ = ledger.supply(.gpu_clock_published, 3);
    try std.testing.expectEqual(Element.hsio_lock_initialised, ledger.firstGap().?);
    try std.testing.expectEqual(State.supplied, ledger.state(.gpu_clock_published));
    try std.testing.expectEqual(State.established, ledger.state(.memory_view_base_discovered));
    try std.testing.expect(ledger.state(.gpu_clock_published).present());
}

test "the actionable list is exactly the platform work the harness has not done" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    var buffer: [element_count]Element = undefined;
    const pending = ledger.outstandingPlatformWork(&buffer);
    try std.testing.expectEqual(@as(usize, 3), pending.len);
    for (pending) |element| {
        try std.testing.expectEqual(Owner.platform, element.owner());
        try std.testing.expect(!ledger.state(element).present());
    }
    try std.testing.expectEqual(Element.kernel_variable_slots_bound, pending[0]);
}

// The aperture element is about reachability, not usage. Defined as "a guest
// store arrived" it could never be satisfied by a title that programs its GPU
// through kernel exports, and it sat ABSENT accusing the emulator forever.
test "the aperture is satisfied by reachability rather than by usage" {
    var ledger = Ledger{};
    inline for (.{
        Element.memory_view_base_discovered, Element.kernel_variable_slots_bound,
        Element.gpu_clock_published,         Element.hsio_lock_initialised,
    }) |element| ledger.observe(element, 1);

    try std.testing.expectEqual(Element.register_aperture_reachable, ledger.firstGap().?);
    try std.testing.expect(Element.register_aperture_reachable.required());

    // A registered handler is the emulator stating the aperture is reachable,
    // and no guest store is needed for it.
    ledger.observe(.register_aperture_reachable, 2);
    try std.testing.expectEqual(Element.engines_initialised, ledger.firstGap().?);
    try std.testing.expectEqual(@as(u32, 5), ledger.establishedCount());
    try std.testing.expect(std.mem.indexOf(u8, Element.register_aperture_reachable.consequence(), "reachability, not usage") != null);
}

// The whole ladder must be reachable, or a report can never say the run is
// clean and the operator learns to ignore the count.
test "every element is required so the ladder can actually be completed" {
    var ledger = Ledger{};
    inline for (@typeInfo(Element).@"enum".fields) |field| {
        const element: Element = @enumFromInt(field.value);
        try std.testing.expect(element.required());
        ledger.observe(element, field.value + 1);
    }
    try std.testing.expect(ledger.firstGap() == null);
    try std.testing.expectEqual(@as(u32, element_count), ledger.establishedCount());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "not what is stopping this run") != null);
}

test "the verdict names the owner of the first gap so the next move is unambiguous" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "harness owns") != null);

    inline for (.{
        Element.kernel_variable_slots_bound, Element.gpu_clock_published,
        Element.hsio_lock_initialised,       Element.register_aperture_reachable,
        Element.engines_initialised,
    }) |element| ledger.observe(element, 2);
    // Next gap is the title's callback registration.
    try std.testing.expectEqual(Owner.title, ledger.firstGap().?.owner());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "title's own decision") != null);
}

// A bounded list that silently truncates would let a report claim it has shown
// every inversion when it has shown eight.
test "inversions past the retained window are counted rather than dropped silently" {
    var ledger = Ledger{};
    // Observed in reverse dependency order, so every element with a
    // prerequisite meets one that has not happened yet. Walking forwards would
    // establish each prerequisite one step before it was needed and produce
    // exactly one inversion, which is the correctly-ordered case.
    var index: u8 = element_count;
    while (index > 0) {
        index -= 1;
        const element: Element = @enumFromInt(index);
        if (element.prerequisite() == null) continue;
        ledger.observe(element, index);
    }
    try std.testing.expectEqual(@as(u32, max_inversions), ledger.inversion_count);
    try std.testing.expect(ledger.inversions_dropped > 0);
}

test "re-observing an established element neither reorders nor re-inverts it" {
    var ledger = Ledger{};
    ledger.observe(.memory_view_base_discovered, 1);
    ledger.observe(.kernel_variable_slots_bound, 2);
    ledger.observe(.gpu_clock_published, 3);
    ledger.observe(.gpu_clock_published, 99);
    try std.testing.expectEqual(@as(u64, 3), ledger.entries[@intFromEnum(Element.gpu_clock_published)].step);
    try std.testing.expectEqual(@as(u64, 2), ledger.entries[@intFromEnum(Element.gpu_clock_published)].observations);
    try std.testing.expectEqual(@as(u32, 0), ledger.inversion_count);
}

test "every element names an owner, a consequence and a label" {
    inline for (@typeInfo(Element).@"enum".fields) |field| {
        const element: Element = @enumFromInt(field.value);
        try std.testing.expect(element.label().len > 0);
        try std.testing.expect(element.consequence().len > 30);
        // A prerequisite must come earlier in the enum, or the ordering check
        // would fire on a correctly ordered run.
        if (element.prerequisite()) |required| {
            try std.testing.expect(@intFromEnum(required) < @intFromEnum(element));
        }
    }
}
