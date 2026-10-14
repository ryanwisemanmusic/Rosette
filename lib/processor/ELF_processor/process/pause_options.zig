/// Runtime controls for the two independent PAUSE optimizations. Keeping
/// these together avoids growing the already-large process state declaration.
pub const Options = struct {
    scheduler_batches_enabled: bool = true,
    counter_batches_enabled: bool = true,
    helper_preserves_state: bool = true,

    pub fn configureFromEnvironment(self: *Options, is_disabled: anytype) void {
        self.scheduler_batches_enabled = !is_disabled("ROSETTE_PE64_PAUSE_BATCHES");
        self.counter_batches_enabled = !is_disabled("ROSETTE_PE64_PAUSE_COUNTER_BATCHES");
    }
};
