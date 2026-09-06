//! By what route the GPU is supposed to tell the title its work finished, and
//! whether anything has ever travelled down it.
//!
//! ## The question this exists to answer
//!
//! A title that submits one batch of draws and then never submits again is not
//! stalled on the GPU. It is waiting to be told the GPU is done, and on the
//! Xbox 360 there are only a small number of ways it can be told:
//!
//! * the **graphics interrupt callback** it registered with
//!   `VdSetGraphicsInterruptCallback`, entered from the emulator's vblank and
//!   command-processor interrupts;
//! * the **read-pointer write-back**, a word in guest memory the command
//!   processor keeps updated with how far it has drained, requested by
//!   `VdEnableRingBufferRPtrWriteBack`;
//! * the **vblank counter** the title polls for timing;
//! * a **fence value** the command processor writes into guest memory in
//!   response to an `EVENT_WRITE` packet the title encoded.
//!
//! Every previous report answered "is the GPU stalled?" and none of them
//! answered "does the title have any way of finding out that it is not?" Those
//! are different questions with different owners, and a run where the answer
//! to the second is *no* looks exactly like a GPU stall while being nothing of
//! the sort.
//!
//! ## Established is not live
//!
//! The distinction this module is built around: a route can be **established**
//! — the title asked for it, the emulator agreed — and still **inert**, with
//! nothing ever having arrived. `VdEnableRingBufferRPtrWriteBack` returning
//! successfully proves the title asked. It proves nothing whatsoever about
//! whether the word at the address it named has ever changed, and that word
//! changing is the entire point of the call.
//!
//! So each route carries three separate facts — requested, established, and
//! *delivered at least once* — and the verdict is computed from the third.
//! A run with one established route and zero deliveries has a precise finding
//! with a named owner, which is what "the producer went quiet" never was.
//!
//! ## What it never does
//!
//! It does not deliver a completion. Writing a plausible read-pointer value
//! into the title's write-back word would move the run and destroy the only
//! honest signal in it: the title would proceed on a number Rosette invented,
//! and the next failure would be attributed to the GPU.

const std = @import("std");

/// The ways a finished frame can be reported back to a title.
pub const Route = enum(u8) {
    /// The title's own callback, entered from the emulator's interrupt
    /// dispatch. The primary route for every retail title.
    interrupt_callback,
    /// A word in guest memory the command processor keeps at the ring's read
    /// pointer. The title polls it to learn how much has drained.
    read_pointer_write_back,
    /// The vblank counter the title reads for frame pacing.
    vblank_counter,
    /// A value the command processor writes in response to an EVENT_WRITE
    /// packet the title encoded into its own command stream.
    command_stream_fence,

    pub fn label(self: Route) []const u8 {
        return switch (self) {
            .interrupt_callback => "graphics interrupt callback",
            .read_pointer_write_back => "read-pointer write-back",
            .vblank_counter => "vblank counter",
            .command_stream_fence => "command-stream fence",
        };
    }

    /// Who owns the delivery once the route is established. This decides
    /// whether an inert route is the emulator's defect or the title's choice.
    pub fn deliveryOwner(self: Route) []const u8 {
        return switch (self) {
            .interrupt_callback => "emulator:graphics-system",
            .read_pointer_write_back => "emulator:command-processor",
            .vblank_counter => "emulator:graphics-system",
            .command_stream_fence => "emulator:command-processor",
        };
    }

    /// Whether the route delivers to a guest address the title itself named.
    ///
    /// The interrupt callback and the write-back word are addresses the title
    /// passed in, and an address it did not pass in is a different route
    /// wearing this one's name. The vblank counter is a register the title
    /// polls rather than somewhere the emulator writes, so it has no address to
    /// check and `established` is decided by the pump running instead.
    pub fn hasGuestAddress(self: Route) bool {
        return switch (self) {
            .interrupt_callback, .read_pointer_write_back, .command_stream_fence => true,
            .vblank_counter => false,
        };
    }

    /// How Rosette can observe this route. The vblank route is deliberately
    /// addressless: the ledger observes the graphics-system boundary itself,
    /// while the title's private counter address is not part of the contract.
    /// Calling that state `UNSAMPLED` would imply a missing read when there is
    /// no valid address to read.
    pub fn valueObservation(self: Route) []const u8 {
        return switch (self) {
            .interrupt_callback => "control-entry",
            .read_pointer_write_back => "guest-memory-readback",
            .vblank_counter => "vblank-boundary-no-guest-address",
            .command_stream_fence => "guest-memory-readback",
        };
    }

    /// Whether this route reaches the title by a *value the title reads*
    /// rather than by control arriving in its code.
    ///
    /// The distinction decides what a delivery has to prove. Entering the
    /// title's callback is the delivery for `interrupt_callback`, and the
    /// value beside it means nothing. For everything else the title is
    /// polling, and a word rewritten with the same number forever has
    /// delivered nothing however many times the emulator wrote it — which is
    /// what this module's own preamble says and what its `live` predicate did
    /// not check: the 2026-09-01 run reported the vblank counter as `live`
    /// with eighty-seven deliveries and a value that had never changed.
    pub fn deliversByValueChange(self: Route) bool {
        return switch (self) {
            .interrupt_callback => false,
            .read_pointer_write_back, .vblank_counter, .command_stream_fence => true,
        };
    }

    /// What an established-but-inert route means. These sentences are the
    /// finding; the counters beside them are only how it was reached.
    pub fn inertMeans(self: Route) []const u8 {
        return switch (self) {
            .interrupt_callback => "the title registered a callback and the emulator has never entered it. The title is waiting on an interrupt that is not being delivered, which is an emulator defect and not a title one — check that the vblank pump is still running and that the dispatch is not returning early on a null or unresolvable callback address",
            .read_pointer_write_back => "the title asked the command processor to mirror the ring read pointer into guest memory and the word it named has never changed. Every poll the title makes reads its initial value, so as far as the title can tell the GPU has consumed nothing — no matter how many packets the command processor actually drained",
            .vblank_counter => "the vblank counter the title polls has never advanced, so nothing is pacing its frame loop",
            .command_stream_fence => "the title encoded a fence into its command stream and the command processor has never written the value back. The title is polling memory that will never change",
        };
    }
};

pub const route_count: usize = @typeInfo(Route).@"enum".fields.len;

/// What is known about one route.
pub const Status = struct {
    /// An address something other than the title placed in this route's slot.
    ///
    /// The emulator's macOS fork installs a Xenia-owned host callback when the
    /// title has not registered one, and once it is there every dispatch into
    /// it looks like a delivery. It is not: the title's own callback is still
    /// unreached, and counting these as deliveries is a harness satisfying a
    /// clause the guest owns — the exact failure this whole subsystem exists to
    /// refuse. They are counted separately and never make a route live.
    foreign_address: u32 = 0,
    foreign_deliveries: u64 = 0,
    /// The address of the last foreign occupant that has since been displaced
    /// by the title, and how many times that has happened.
    ///
    /// A slot changes hands. Rosette's host callback is installed at step
    /// 627 830 984 and the title's own registration replaces it at step
    /// 2 864 593 199 — after which every dispatch goes to the title. A ledger
    /// that latched the first occupant reported `deliveries=0 INERT: the
    /// emulator has never entered it` for the remaining four and a half
    /// billion steps of a run in which the title's callback ran two hundred
    /// and forty times. The occupancy is therefore current state, and the
    /// displaced address is kept here so the history is not lost with it.
    displaced_foreign_address: u32 = 0,
    foreign_releases: u32 = 0,
    /// The title asked for this route — the export shim was entered, or the
    /// packet was decoded.
    requested: bool = false,
    /// The emulator accepted it and has somewhere to deliver to. For the
    /// callback this is a non-zero registered address; for the write-back a
    /// non-zero guest address.
    established: bool = false,
    /// The guest-visible address the route delivers to, when it has one.
    /// Zero is meaningful: an established route with no address is a route the
    /// emulator accepted and cannot use.
    address: u32 = 0,
    /// Deliveries the emulator attempted.
    attempts: u64 = 0,
    /// Deliveries whose *effect on the guest* was observed: the callback
    /// entered guest code, or the written word changed value. This is the
    /// only field that proves the route works.
    deliveries: u64 = 0,
    /// The value last seen at `address`, and whether it has ever differed
    /// from the first value seen. A word that is being written with the same
    /// value forever is inert in every way that matters to a poller.
    first_value: u32 = 0,
    last_value: u32 = 0,
    value_seen: bool = false,
    value_changed: bool = false,
    requested_step: u64 = 0,
    first_delivery_step: u64 = 0,
    last_delivery_step: u64 = 0,

    /// Whether something other than the title occupies this route's slot.
    pub fn occupied(self: Status) bool {
        return self.foreign_address != 0;
    }

    /// Established, and something has actually arrived *at the title's own
    /// address*. A foreign occupant can never make this true.
    ///
    /// `route` is required because what counts as arrival differs: control
    /// entering the title's callback, or a value the title polls actually
    /// moving. A polled word rewritten with the same number is not an arrival.
    pub fn liveFor(self: Status, route: Route) bool {
        if (!self.established or self.occupied() or self.deliveries == 0) return false;
        if (!route.deliversByValueChange()) return true;
        // A value nobody has read yet cannot contradict the delivery count.
        if (!self.value_seen) return true;
        return self.value_changed;
    }

    /// Established, delivered, and the value the title polls has never moved.
    ///
    /// The state that reads healthiest and helps least: the emulator ran its
    /// delivery path, the counters climbed, and a title polling that word saw
    /// the same number every time.
    pub fn deliveredWithoutChange(self: Status, route: Route) bool {
        return self.established and
            self.deliveries != 0 and
            route.deliversByValueChange() and
            self.value_seen and
            !self.value_changed;
    }

    /// Established, and nothing has ever arrived. The finding.
    pub fn inert(self: Status) bool {
        return self.established and self.deliveries == 0;
    }

    /// The route is being delivered to and the title is not the recipient. The
    /// most misleading state a completion route can be in, because every
    /// counter reads healthy and the title is still waiting.
    pub fn hijacked(self: Status) bool {
        return self.occupied() and self.foreign_deliveries != 0;
    }

    /// Attempted deliveries that produced no observable effect. Distinct from
    /// inert: the emulator ran its delivery path and the guest saw nothing,
    /// which points at the delivery rather than at the pump.
    pub fn attemptedWithoutEffect(self: Status) bool {
        return self.attempts != 0 and self.deliveries == 0;
    }
};

pub const Verdict = enum(u8) {
    /// The title has not asked for any route yet. It cannot be waiting on one.
    none_requested,
    /// A route the title asked for is being delivered to an address the title
    /// did not name. Ranked above every other verdict because every counter
    /// downstream of it reads healthy while the title receives nothing.
    hijacked,
    /// The title asked and the emulator established nothing. The route the
    /// title believes it has does not exist.
    requested_but_not_established,
    /// At least one route is established and not one delivery has been
    /// observed on any of them. The title is waiting on a channel that has
    /// never carried anything.
    established_but_inert,
    /// A route delivered and then stopped.
    delivered_then_stopped,
    /// A route the title polls is being written and its value never moves.
    delivered_without_change,
    /// At least one route is delivering.
    live,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .none_requested => "none_requested",
            .hijacked => "hijacked",
            .requested_but_not_established => "requested_but_not_established",
            .established_but_inert => "established_but_inert",
            .delivered_then_stopped => "delivered_then_stopped",
            .delivered_without_change => "DELIVERED-WITHOUT-CHANGE",
            .live => "live",
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .none_requested => "the title has asked for no completion route, so it is not waiting on one. Whatever it is doing between submissions, it is not blocked on the GPU reporting back",
            .hijacked => "the title registered a completion route and something else is sitting in its slot, so every delivery is going somewhere the title is not listening. This is the worst state a route can be in: dispatch counters climb, the emulator reports success, and the title waits forever. Find what wrote that address and stop it writing over a registration the title made",
            .requested_but_not_established => "the title asked for a completion route and the emulator has not established one. The title believes it has a channel that does not exist, and it will wait on it forever",
            .established_but_inert => "every completion route the title has is established and none of them has ever delivered. This is why a title submits once and stops: the work was consumed and nothing told it so. Look at the delivery owner named below, not at the command processor's packet counters",
            .delivered_then_stopped => "a completion route delivered and then went silent. Find what stopped the deliverer; the title has been waiting on it since",
            .delivered_without_change => "a route the title reads by polling is being written and the value it reads has never moved. Every delivery counter climbs and the title sees the same number every time, so from where it is standing nothing has happened at all. Find what computes the value, not what delivers it",
            .live => "a completion route is delivering. If the title still is not submitting, it is waiting on something other than GPU completion",
        };
    }
};

/// How long a route may be silent after its last delivery before that silence
/// is a finding. Sized like the bring-up gate's budget: about twenty seconds
/// of the observed run rate, long enough that several frames should have
/// passed at any healthy pace.
pub const default_silence_budget: u64 = 100_000_000;

pub const Ledger = struct {
    routes: [route_count]Status = [_]Status{.{}} ** route_count,
    silence_budget: u64 = default_silence_budget,

    pub fn status(self: *const Ledger, route: Route) Status {
        return self.routes[@intFromEnum(route)];
    }

    /// The title asked for this route.
    pub fn noteRequested(self: *Ledger, route: Route, step: u64) void {
        const slot = &self.routes[@intFromEnum(route)];
        if (!slot.requested) slot.requested_step = step;
        slot.requested = true;
    }

    /// The emulator has somewhere to deliver to. A zero address deliberately
    /// does not establish the route: a callback registered as zero and a
    /// write-back pointed at address zero are both routes that will silently
    /// swallow every delivery, and reporting them as established is how an
    /// inert channel reads healthy.
    pub fn noteEstablished(self: *Ledger, route: Route, address: u32, step: u64) void {
        const slot = &self.routes[@intFromEnum(route)];
        if (!slot.requested) {
            slot.requested = true;
            slot.requested_step = step;
        }
        if (!route.hasGuestAddress()) {
            // The vblank counter is a register the title polls, not somewhere
            // the emulator writes. Establishing it by the pump running keeps a
            // placeholder address — `address=0x00000001` in the first pass —
            // out of a report where every other address is real.
            slot.established = true;
            return;
        }
        slot.address = address;
        slot.established = address != 0;
    }

    /// Something other than the title placed an address in this route's slot.
    ///
    /// Recorded rather than resolved. Rosette does not know whether the
    /// emulator's forced callback overwrote a registration the title made or
    /// merely filled a slot the title left empty — but it does know that
    /// deliveries to this address do not reach the title, and that is enough to
    /// stop them being counted as if they did.
    pub fn noteForeignOccupant(self: *Ledger, route: Route, address: u32) void {
        self.routes[@intFromEnum(route)].foreign_address = address;
    }

    /// The title now owns the slot, so the foreign occupant is history.
    ///
    /// Occupancy is a statement about *now*: it is what decides whether the
    /// next delivery reaches the title. Latching it turned a resolved handover
    /// into a permanent verdict with an owner attached — "an emulator defect
    /// and not a title one" — about a route that had been working for billions
    /// of steps. The displaced address and a release count are retained so a
    /// reader can still see that the handover happened.
    pub fn clearForeignOccupant(self: *Ledger, route: Route) void {
        const slot = &self.routes[@intFromEnum(route)];
        if (slot.foreign_address == 0) return;
        slot.displaced_foreign_address = slot.foreign_address;
        slot.foreign_address = 0;
        slot.foreign_releases +|= 1;
    }

    /// The emulator ran its delivery path. Says nothing about whether the
    /// guest saw anything.
    pub fn noteAttempt(self: *Ledger, route: Route, step: u64) void {
        const slot = &self.routes[@intFromEnum(route)];
        slot.attempts +|= 1;
        slot.last_delivery_step = step;
    }

    /// A delivery whose effect on the guest was observed. The only call that
    /// makes a route live — and only when the title is the recipient.
    ///
    /// A delivery into a slot something else occupies is counted separately.
    /// It is a real event and it is not the title's completion, and the whole
    /// reason this ledger exists is that those two look identical in every
    /// counter the emulator keeps.
    pub fn noteDelivery(self: *Ledger, route: Route, step: u64) void {
        const slot = &self.routes[@intFromEnum(route)];
        slot.last_delivery_step = step;
        if (slot.occupied()) {
            slot.foreign_deliveries +|= 1;
            return;
        }
        if (slot.deliveries == 0) slot.first_delivery_step = step;
        slot.deliveries +|= 1;
    }

    /// A sample of the word a memory-delivered route writes to. A change is
    /// the delivery; repeated identical values are not, however many times
    /// the emulator says it wrote them.
    pub fn sampleValue(self: *Ledger, route: Route, value: u32, step: u64) void {
        const slot = &self.routes[@intFromEnum(route)];
        if (!slot.value_seen) {
            slot.value_seen = true;
            slot.first_value = value;
            slot.last_value = value;
            return;
        }
        if (value == slot.last_value) return;
        slot.last_value = value;
        slot.value_changed = true;
        self.noteDelivery(route, step);
    }

    /// The route a reader should act on: the established one with the fewest
    /// deliveries, preferring the title's primary route when they tie. A run
    /// with one inert route and one live one is not stuck; a run with two
    /// inert routes has one finding, not two.
    pub fn weakestEstablished(self: *const Ledger) ?Route {
        var chosen: ?Route = null;
        inline for (@typeInfo(Route).@"enum".fields) |field| {
            const route: Route = @enumFromInt(field.value);
            const slot = self.routes[field.value];
            if (slot.established) {
                if (chosen) |held| {
                    if (slot.deliveries < self.routes[@intFromEnum(held)].deliveries) {
                        chosen = route;
                    }
                } else {
                    chosen = route;
                }
            }
        }
        return chosen;
    }

    pub fn establishedCount(self: *const Ledger) u8 {
        var total: u8 = 0;
        for (self.routes) |slot| {
            if (slot.established) total += 1;
        }
        return total;
    }

    /// Number of routes the title actually requested. The enum count is the
    /// vocabulary of possible routes, not the denominator for a run: an
    /// unrequested command-stream fence is not a missing completion channel.
    pub fn requestedCount(self: *const Ledger) u8 {
        var total: u8 = 0;
        for (self.routes) |slot| {
            if (slot.requested) total += 1;
        }
        return total;
    }

    pub fn liveCount(self: *const Ledger) u8 {
        var total: u8 = 0;
        for (self.routes, 0..) |slot, index| {
            if (slot.liveFor(@enumFromInt(index))) total += 1;
        }
        return total;
    }

    /// Routes being written whose polled value has never moved.
    pub fn deliveredWithoutChangeCount(self: *const Ledger) u8 {
        var total: u8 = 0;
        for (self.routes, 0..) |slot, index| {
            if (slot.deliveredWithoutChange(@enumFromInt(index))) total += 1;
        }
        return total;
    }

    pub fn totalDeliveries(self: *const Ledger) u64 {
        var total: u64 = 0;
        for (self.routes) |slot| total +|= slot.deliveries;
        return total;
    }

    pub fn verdict(self: *const Ledger, step: u64) Verdict {
        var any_requested = false;
        var any_established = false;
        var newest_delivery: u64 = 0;
        var any_delivery = false;
        var any_live = false;
        var any_delivered_without_change = false;
        for (self.routes, 0..) |slot, index| {
            const route: Route = @enumFromInt(index);
            if (slot.requested) any_requested = true;
            if (slot.established) any_established = true;
            if (slot.liveFor(route)) any_live = true;
            if (slot.deliveredWithoutChange(route)) any_delivered_without_change = true;
            if (slot.deliveries != 0) {
                any_delivery = true;
                if (slot.last_delivery_step > newest_delivery) {
                    newest_delivery = slot.last_delivery_step;
                }
            }
        }
        if (!any_requested) return .none_requested;
        // A hijacked route outranks everything: its counters read healthy and
        // the title receives nothing, so any other verdict computed alongside
        // it would be describing a pipeline that is not the one running.
        for (self.routes) |slot| {
            if (slot.hijacked()) return .hijacked;
        }
        if (!any_established) return .requested_but_not_established;
        if (!any_delivery) return .established_but_inert;
        // A polled route being written with an unchanging value outranks
        // `live`, and only when nothing else is genuinely delivering. A run
        // with a working write-back and a frozen vblank counter is live, and
        // the frozen route is still named on its own row.
        if (!any_live and any_delivered_without_change) return .delivered_without_change;
        if (step > newest_delivery and step - newest_delivery > self.silence_budget) {
            return .delivered_then_stopped;
        }
        return .live;
    }
};

test "a route with no address is not established" {
    var ledger = Ledger{};
    ledger.noteEstablished(.interrupt_callback, 0, 100);
    try std.testing.expect(!ledger.status(.interrupt_callback).established);
    try std.testing.expectEqual(
        Verdict.requested_but_not_established,
        ledger.verdict(1_000),
    );
}

// The finding the observed run needed and did not have.
test "an established route that never delivered is the finding" {
    var ledger = Ledger{};
    ledger.noteEstablished(.read_pointer_write_back, 0x8200_1000, 3_036_335_775);
    ledger.noteAttempt(.read_pointer_write_back, 3_400_000_000);
    ledger.noteAttempt(.read_pointer_write_back, 3_500_000_000);
    const out = ledger.verdict(5_000_000_000);
    try std.testing.expectEqual(Verdict.established_but_inert, out);
    const slot = ledger.status(.read_pointer_write_back);
    try std.testing.expect(slot.inert());
    try std.testing.expect(slot.attemptedWithoutEffect());
    try std.testing.expectEqual(
        Route.read_pointer_write_back,
        ledger.weakestEstablished().?,
    );
}

// A word written with the same value forever is inert to a poller, however
// many times the emulator reports writing it.
test "an unchanged write-back word is not a delivery" {
    var ledger = Ledger{};
    ledger.noteEstablished(.read_pointer_write_back, 0x8200_1000, 10);
    ledger.sampleValue(.read_pointer_write_back, 0, 100);
    ledger.sampleValue(.read_pointer_write_back, 0, 200);
    ledger.sampleValue(.read_pointer_write_back, 0, 300);
    try std.testing.expect(!ledger.status(.read_pointer_write_back).value_changed);
    try std.testing.expectEqual(Verdict.established_but_inert, ledger.verdict(400));

    ledger.sampleValue(.read_pointer_write_back, 25, 400);
    try std.testing.expect(ledger.status(.read_pointer_write_back).value_changed);
    try std.testing.expectEqual(Verdict.live, ledger.verdict(410));
}

test "a route that delivered and stopped is distinguished from one that never did" {
    var ledger = Ledger{};
    ledger.noteEstablished(.interrupt_callback, 0x8200_4000, 10);
    ledger.noteDelivery(.interrupt_callback, 974_046_863);
    try std.testing.expectEqual(Verdict.live, ledger.verdict(1_000_000_000));
    try std.testing.expectEqual(Verdict.delivered_then_stopped, ledger.verdict(5_000_000_000));
}

test "no requested route means the title is not waiting on completion" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.none_requested, ledger.verdict(5_000_000_000));
    try std.testing.expect(ledger.weakestEstablished() == null);
}

test "the weakest established route is the one to act on" {
    var ledger = Ledger{};
    ledger.noteEstablished(.interrupt_callback, 0x8200_4000, 10);
    ledger.noteEstablished(.read_pointer_write_back, 0x8200_1000, 20);
    ledger.noteDelivery(.interrupt_callback, 30);
    try std.testing.expectEqual(
        Route.read_pointer_write_back,
        ledger.weakestEstablished().?,
    );
    try std.testing.expectEqual(@as(u8, 2), ledger.establishedCount());
    try std.testing.expectEqual(@as(u8, 1), ledger.liveCount());
    try std.testing.expectEqual(Verdict.live, ledger.verdict(40));
}

test "every route explains what its own inertness means" {
    inline for (@typeInfo(Route).@"enum".fields) |field| {
        const route: Route = @enumFromInt(field.value);
        try std.testing.expect(route.label().len != 0);
        try std.testing.expect(route.inertMeans().len != 0);
        try std.testing.expect(route.deliveryOwner().len != 0);
    }
}

// The 2026-08-30 20:08 reading. The title registered its own callback at guest
// step 3_005_381_071, the emulator's forced host callback 0xFFFF0010 sat in the
// slot, and 34 dispatches were counted as deliveries on a route whose
// `established` flag was NO and whose address was zero. The summary read
// `live`. Every one of those dispatches went somewhere the title was not.
test "deliveries into a foreign occupant never make a route live" {
    var ledger = Ledger{};
    ledger.noteRequested(.interrupt_callback, 3_005_381_071);
    ledger.noteForeignOccupant(.interrupt_callback, 0xFFFF_0010);
    var index: u32 = 0;
    while (index < 34) : (index += 1) {
        ledger.noteDelivery(.interrupt_callback, 3_400_000_000 + index);
    }
    const slot = ledger.status(.interrupt_callback);
    try std.testing.expectEqual(@as(u64, 0), slot.deliveries);
    try std.testing.expectEqual(@as(u64, 34), slot.foreign_deliveries);
    try std.testing.expect(!slot.liveFor(.interrupt_callback));
    try std.testing.expect(slot.hijacked());
    try std.testing.expectEqual(Verdict.hijacked, ledger.verdict(4_200_000_000));
    try std.testing.expectEqual(@as(u8, 0), ledger.liveCount());
}

// Giving the vblank counter a placeholder address printed `address=0x00000001`,
// which is a number in the report that means nothing.
test "an addressless route is established without inventing an address" {
    var ledger = Ledger{};
    ledger.noteEstablished(.vblank_counter, 0, 100);
    const slot = ledger.status(.vblank_counter);
    try std.testing.expect(slot.established);
    try std.testing.expectEqual(@as(u32, 0), slot.address);
    ledger.noteDelivery(.vblank_counter, 200);
    // No value has been observed yet, so the delivery count stands.
    try std.testing.expect(ledger.status(.vblank_counter).liveFor(.vblank_counter));
}

// The 2026-08-31 reading, and the reason occupancy stopped being a latch. The
// emulator installed its host callback 0xFFFF0010 at step 627 830 984; the
// title registered its own at 2 864 593 199 and the emulator entered it two
// hundred and forty times after that. The route still reported
// `deliveries=0` and `INERT: the title registered a callback and the emulator
// has never entered it ... which is an emulator defect and not a title one`,
// which is a verdict, with an owner, about a mechanism that was working.
test "a slot the title takes back stops counting deliveries as foreign" {
    var ledger = Ledger{};
    ledger.noteRequested(.interrupt_callback, 627_830_984);
    ledger.noteForeignOccupant(.interrupt_callback, 0xFFFF_0010);
    ledger.noteDelivery(.interrupt_callback, 700_000_000);
    try std.testing.expectEqual(@as(u64, 1), ledger.status(.interrupt_callback).foreign_deliveries);

    ledger.noteEstablished(.interrupt_callback, 0x8219_51F8, 2_864_593_199);
    ledger.clearForeignOccupant(.interrupt_callback);
    ledger.noteDelivery(.interrupt_callback, 2_957_476_424);

    const slot = ledger.status(.interrupt_callback);
    try std.testing.expect(!slot.occupied());
    try std.testing.expect(!slot.hijacked());
    try std.testing.expect(slot.liveFor(.interrupt_callback));
    try std.testing.expect(!slot.inert());
    try std.testing.expectEqual(@as(u64, 1), slot.deliveries);
    // The handover is still legible after the release.
    try std.testing.expectEqual(@as(u32, 0xFFFF_0010), slot.displaced_foreign_address);
    try std.testing.expectEqual(@as(u32, 1), slot.foreign_releases);
    try std.testing.expectEqual(@as(u64, 1), slot.foreign_deliveries);
}

test "releasing a slot nothing occupies changes nothing" {
    var ledger = Ledger{};
    ledger.noteEstablished(.interrupt_callback, 0x8219_51F8, 100);
    ledger.clearForeignOccupant(.interrupt_callback);
    const slot = ledger.status(.interrupt_callback);
    try std.testing.expectEqual(@as(u32, 0), slot.displaced_foreign_address);
    try std.testing.expectEqual(@as(u32, 0), slot.foreign_releases);
}

// The 2026-09-01 reading: `vblank counter requested=YES established=YES
// deliveries=87 value(first/last/changed)=0x0/0x0/NO`, and the ledger called
// it live. The module's own preamble says a word rewritten with the same value
// forever is inert in every way that matters to a poller; the predicate did
// not check it.
test "a polled route whose value never moves is not delivering" {
    var ledger = Ledger{};
    ledger.noteEstablished(.vblank_counter, 0, 100);
    var tick: u64 = 0;
    while (tick < 87) : (tick += 1) {
        ledger.noteDelivery(.vblank_counter, 200 + tick);
        ledger.sampleValue(.vblank_counter, 0, 200 + tick);
    }

    const slot = ledger.status(.vblank_counter);
    try std.testing.expectEqual(@as(u64, 87), slot.deliveries);
    try std.testing.expect(slot.value_seen);
    try std.testing.expect(!slot.value_changed);
    try std.testing.expect(!slot.liveFor(.vblank_counter));
    try std.testing.expect(slot.deliveredWithoutChange(.vblank_counter));
    try std.testing.expectEqual(@as(u8, 0), ledger.liveCount());
    try std.testing.expectEqual(@as(u8, 1), ledger.deliveredWithoutChangeCount());

    const verdict = ledger.verdict(400);
    try std.testing.expectEqual(Verdict.delivered_without_change, verdict);
    try std.testing.expect(std.mem.indexOf(u8, verdict.describe(), "not what delivers it") != null);
}

// The callback's delivery is control arriving in the title's code, so the
// value beside it must not be allowed to contradict it.
test "an interrupt callback is not judged by a value" {
    var ledger = Ledger{};
    ledger.noteEstablished(.interrupt_callback, 0x8219_51F8, 100);
    ledger.noteDelivery(.interrupt_callback, 200);
    ledger.sampleValue(.interrupt_callback, 0, 210);
    ledger.sampleValue(.interrupt_callback, 0, 210);

    const slot = ledger.status(.interrupt_callback);
    try std.testing.expect(slot.value_seen);
    try std.testing.expect(!slot.value_changed);
    try std.testing.expect(slot.liveFor(.interrupt_callback));
    try std.testing.expect(!slot.deliveredWithoutChange(.interrupt_callback));
    try std.testing.expect(!Route.interrupt_callback.deliversByValueChange());
}

// One frozen polled route beside one that is genuinely moving is a live run
// with a named row, not a stalled one. The verdict must not be dominated by
// the quietest route.
test "a frozen route beside a moving one does not take the verdict" {
    var ledger = Ledger{};
    ledger.noteEstablished(.read_pointer_write_back, 0x050E_F03C, 100);
    ledger.noteDelivery(.read_pointer_write_back, 200);
    ledger.sampleValue(.read_pointer_write_back, 0, 201);
    ledger.sampleValue(.read_pointer_write_back, 0x19, 202);

    ledger.noteEstablished(.vblank_counter, 0, 100);
    ledger.noteDelivery(.vblank_counter, 210);
    ledger.sampleValue(.vblank_counter, 0, 211);
    ledger.sampleValue(.vblank_counter, 0, 212);

    try std.testing.expect(ledger.status(.read_pointer_write_back).liveFor(.read_pointer_write_back));
    try std.testing.expect(ledger.status(.vblank_counter).deliveredWithoutChange(.vblank_counter));
    try std.testing.expectEqual(Verdict.live, ledger.verdict(250));
    try std.testing.expectEqual(@as(u8, 1), ledger.liveCount());
    try std.testing.expectEqual(@as(u8, 1), ledger.deliveredWithoutChangeCount());
}
