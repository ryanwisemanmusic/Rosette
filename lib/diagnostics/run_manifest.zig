//! What this run is, what it was allowed to do, and whether two runs are
//! comparable at all.
//!
//! The defect this exists for
//! --------------------------
//! A run's posture currently lives in a dozen independent booleans. Reading
//! them individually, a run can look authentic while a fallback is quietly
//! active — and worse, a flag that is enabled but whose predicate never fired
//! is indistinguishable from one that is off. `gpu_debug_force_swap_once` is
//! harmless today only because `gpu_debug_force_swap_after_ms` is zero, and
//! nothing in the run says so.
//!
//! The manifest replaces that with one declared mode and an enumerated list of
//! interventions, written once at the start and carried into every frame
//! provenance record. It also carries the identity a second run has to match
//! before the two can be compared: image hash, media hash, config hash. Two
//! runs of different builds producing different frontiers is not a finding.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const RunIdentity = bridge.contract.RunIdentity;
pub const SourceClass = bridge.contract.SourceClass;
pub const FeatureSet = bridge.contract.FeatureSet;
pub const Feature = bridge.contract.Feature;

/// Parse the process-wide execution posture.  The environment is an input to
/// the run, not a convenience override: an unrecognised value is therefore
/// returned as `null` so the caller can keep the manifest unsealed and fail
/// closed instead of silently choosing a more permissive mode.
pub fn parseProfile(raw: []const u8) ?Profile {
    const value = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(value, "authentic")) return .authentic;
    if (std.ascii.eqlIgnoreCase(value, "diagnostic")) return .diagnostic;
    if (std.ascii.eqlIgnoreCase(value, "synthetic")) return .synthetic;
    if (std.ascii.eqlIgnoreCase(value, "replay")) return .replay;
    return null;
}

pub fn hashIdentityBytes(bytes: []const u8) u64 {
    var hash: u64 = 0xcbf2_9ce4_8422_2325;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 0x0100_0000_01b3;
    }
    return hash;
}

/// Hash a labelled value using the same content-addressed convention as the
/// build-identity generator.  Labels are part of the identity so that, for
/// example, the string `default` used for a scheduler policy cannot be
/// mistaken for the same value used for a backend selection.
pub fn hashIdentityTag(label: []const u8, value: []const u8) u64 {
    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    digest.update(label);
    digest.update(&[_]u8{0});
    digest.update(value);
    const result = digest.finalResult();
    const hash = std.mem.readInt(u64, result[0..8], .big);
    return if (hash == 0) 1 else hash;
}

// Keep the fallback identical to tools/build_identity_manifest.py's schema
// identity. The JSON document version and this compact field are separate:
// the former describes the envelope, while this value identifies the
// Rosette/Xenia contract that the runtime records implement.
pub const build_identity_schema_value = "rosette-xenia-v2";

/// Optional observer for a content hash. The callback is deliberately small
/// and infrequent: it exists to make a multi-gigabyte launch input observable,
/// not to put a progress event on every read.
pub const FileHashProgressFn = *const fn (bytes_read: u64, total_bytes: ?u64) void;

/// An external volume can transiently reject a read while it is recovering a
/// block. A retry observer makes that recovery visible without putting a
/// logging operation in the normal read path.
pub const FileHashRetryFn = *const fn (
    offset: u64,
    attempt: u32,
    chunk_bytes: usize,
    error_name: []const u8,
    wait_ns: u64,
) void;

/// A content hash is never valid when the complete input could not be read.
/// The failure observer carries the exact byte offset so a host I/O failure is
/// distinguishable from a parser or admission failure in the retained log.
pub const FileHashFailureFn = *const fn (
    offset: u64,
    total_bytes: ?u64,
    attempts: u32,
    chunk_bytes: usize,
    error_name: []const u8,
    wait_ns: u64,
) void;

/// Who owns a launch-input read fault.
///
/// A digest that stops partway through says only that the run cannot certify
/// its input. It does not say whether the image is wrong or the volume under
/// it is failing, and those demand opposite responses: repackage the title, or
/// stop trusting the device. The audit names an owner only where the evidence
/// actually separates them, and says `undetermined` where it does not.
pub const InputFaultOwner = enum {
    /// Every byte of the declared size is allocated and the file is unchanged,
    /// yet the volume refuses a region of it. The image is the victim here,
    /// not the cause.
    host_media,
    /// The file ends before its declared size, or holds fewer blocks than its
    /// length claims. It was never written whole.
    input_truncated,
    /// The file was replaced or resized while the digest was running.
    input_replaced,
    /// The evidence does not separate the cases.
    undetermined,

    pub fn text(self: InputFaultOwner) []const u8 {
        return switch (self) {
            .host_media => "host-media",
            .input_truncated => "input-truncated",
            .input_replaced => "input-replaced",
            .undetermined => "undetermined",
        };
    }
};

/// A bounded probe of the unreadable region, run after the digest has already
/// failed.
///
/// The probe deliberately never walks the region linearly. A failing device
/// spends its own internal retry budget on every rejected request, so a linear
/// walk pays that stall once per block and is indistinguishable from a hang.
/// Galloping to the first readable offset and then bisecting keeps the number
/// of *failing* reads logarithmic in the size of the hole, which is the term
/// that actually bounds the wall time.
pub const InputDamageSurvey = struct {
    /// Digest offset the failing request was issued at. The request covered a
    /// window, so this is where the search starts, not where the damage is.
    scan_start: u64 = 0,
    /// First offset confirmed unreadable by a probe of its own. `null` means
    /// the whole failed window re-read cleanly, which makes the original
    /// fault transient rather than a hole.
    first_fault_offset: ?u64 = null,
    /// First offset at or after `start_offset` that read cleanly, when the
    /// probe found one inside its budget.
    resume_offset: ?u64 = null,
    /// Whether the file's final probe-sized window still reads. A localized
    /// hole and a volume that has stopped answering past a point present the
    /// same way at the digest offset, and are different problems.
    tail_readable: ?bool = null,
    probe_bytes: usize = 0,
    probes_attempted: u32 = 0,
    probes_failed: u32 = 0,
    elapsed_ns: u64 = 0,
    /// The budget ran out before readable data was found. Any extent derived
    /// from the survey is then a floor on the damage, never its size.
    budget_exhausted: bool = false,

    pub fn damagedBytes(self: InputDamageSurvey) ?u64 {
        const resumed = self.resume_offset orelse return null;
        const began = self.first_fault_offset orelse return null;
        return if (resumed > began) resumed - began else 0;
    }
};

/// Everything the audit established about a launch input it could not hash.
pub const InputFaultDiagnosis = struct {
    owner: InputFaultOwner = .undetermined,
    /// Digest offset the failing read was issued at.
    offset: u64 = 0,
    request_bytes: usize = 0,
    error_name: []const u8 = "",
    /// Wall time the failing read spent in the kernel before it returned. A
    /// device exhausting its own retry budget takes tens of seconds; a
    /// filesystem-level refusal returns at once. The two carry the same error
    /// name and are told apart nowhere else.
    fault_wait_ns: u64 = 0,
    recovery_events: u32 = 0,
    logical_size: ?u64 = null,
    /// Bytes the filesystem has actually allocated to the file. A fully
    /// allocated file that cannot be read back was written whole and damaged
    /// afterwards; a short allocation was never written whole at all.
    allocated_bytes: ?u64 = null,
    survey: ?InputDamageSurvey = null,

    pub fn fullyAllocated(self: InputFaultDiagnosis) ?bool {
        const size = self.logical_size orelse return null;
        const allocated = self.allocated_bytes orelse return null;
        return allocated >= size;
    }
};

/// Reports the diagnosis assembled after a launch input failed to hash. It is
/// separate from the failure observer because it is allowed to cost real time:
/// it runs only once the launch is already refused.
pub const FileHashDiagnosisFn = *const fn (diagnosis: InputFaultDiagnosis) void;

/// Announces the damage survey before it starts, with the budget it may spend.
///
/// The survey is deliberately silent while it runs — every probe it makes is a
/// read, and a read that refuses takes the device's whole retry budget — so a
/// launcher watching for liveness sees nothing for minutes and concludes the
/// process is wedged. It is not; it is answering the question. Declaring the
/// budget up front lets a watchdog wait exactly as long as the runtime said it
/// would, instead of guessing a constant that is either too tight to survive
/// one device retry or too loose to catch a real hang.
pub const FileHashSurveyStartFn = *const fn (offset: u64, budget_ns: u64) void;

/// Bounds recovery from a removable-volume read fault.  Recovery is useful
/// for a transient device error, but it must never turn authentic admission
/// into an unbounded pre-launch wait.  The byte budget is deliberately a
/// clean-byte budget: a persistent bad region cannot reset it by returning a
/// small successful prefix on every request.
pub const FileHashOptions = struct {
    retry_limit: u32 = 3,
    max_recovery_events: u32 = 8,
    max_recovery_time_ns: u64 = 15 * std.time.ns_per_s,
    recovery_reset_bytes: u64 = 8 * 1024 * 1024,
    retry_chunk_bytes: usize = 64 * 1024,
    final_retry_chunk_bytes: usize = 4 * 1024,
    /// Post-mortem probe of the damaged region. It runs only after the digest
    /// has already failed, so its cost falls on a launch that is not going to
    /// proceed, and it buys the operator the extent of the damage in place of
    /// a single offset.
    survey_damage: bool = true,
    survey_probe_bytes: usize = 4 * 1024,
    survey_max_probes: u32 = 64,
    survey_max_time_ns: u64 = 240 * std.time.ns_per_s,
    /// Where the gallop for readable data starts.
    ///
    /// This is the single most expensive choice in the survey. Doubling from
    /// one page walks a hole of any real size one refusal at a time, and each
    /// refusal costs the device's whole internal retry budget. Starting a
    /// megabyte out usually clears the hole on the first probe, which is free
    /// when it succeeds, and the bisection that follows spends most of its
    /// probes on readable offsets.
    survey_gallop_start_bytes: u64 = 1024 * 1024,
    /// How far past the fault the probe may look for readable data. Beyond
    /// this the survey reports a floor rather than pretending to an extent.
    survey_window_bytes: u64 = 256 * 1024 * 1024,
};

/// Runtime knobs for launch-input diagnosis.  The defaults fail closed
/// quickly enough to expose a bad external volume while still allowing a
/// short-lived transient read recovery.  Set a value to zero to disable that
/// particular bound when investigating a known-good but unusually slow device.
pub fn defaultFileHashOptions() FileHashOptions {
    const max_recovery_ms = environmentUnsigned("ROSETTE_INPUT_HASH_MAX_RECOVERY_MS", 15_000, 900_000);
    const max_recovery_events = environmentUnsigned("ROSETTE_INPUT_HASH_MAX_RECOVERY_EVENTS", 8, 4096);
    const recovery_reset_bytes = environmentUnsigned(
        "ROSETTE_INPUT_HASH_RECOVERY_RESET_BYTES",
        8 * 1024 * 1024,
        1024 * 1024 * 1024,
    );
    const retry_limit = environmentUnsigned("ROSETTE_INPUT_HASH_RETRY_LIMIT", 3, 64);
    const survey_max_ms = environmentUnsigned("ROSETTE_INPUT_SURVEY_MAX_MS", 240_000, 900_000);
    const survey_max_probes = environmentUnsigned("ROSETTE_INPUT_SURVEY_MAX_PROBES", 64, 4096);
    const survey_window_bytes = environmentUnsigned(
        "ROSETTE_INPUT_SURVEY_WINDOW_BYTES",
        256 * 1024 * 1024,
        64 * 1024 * 1024 * 1024,
    );
    return .{
        .retry_limit = @intCast(retry_limit),
        .max_recovery_events = @intCast(max_recovery_events),
        .max_recovery_time_ns = max_recovery_ms * std.time.ns_per_ms,
        .recovery_reset_bytes = recovery_reset_bytes,
        .survey_damage = survey_max_ms != 0 and survey_max_probes != 0,
        .survey_max_time_ns = survey_max_ms * std.time.ns_per_ms,
        .survey_max_probes = @intCast(survey_max_probes),
        .survey_window_bytes = survey_window_bytes,
    };
}

/// Hash a file without loading the whole input into memory.  The Python
/// build-identity producer uses SHA-256 and projects its first 64 bits into
/// the compact runtime record, so this is deliberately the same operation.
/// It matters for XISO files: a title image can be several gigabytes and must
/// not be represented by its pathname or by a bounded prefix.
pub fn hashFileContents(io: std.Io, path: []const u8) !u64 {
    return hashFileContentsWithProgressAndRecoveryWithOptions(
        io,
        path,
        null,
        null,
        null,
        defaultFileHashOptions(),
    );
}

pub fn hashFileContentsWithProgress(
    io: std.Io,
    path: []const u8,
    progress: ?FileHashProgressFn,
) !u64 {
    return hashFileContentsWithProgressAndRecoveryWithOptions(
        io,
        path,
        progress,
        null,
        null,
        defaultFileHashOptions(),
    );
}

/// Hash a complete file through exact-offset reads. The old streaming reader
/// was correct for ordinary files, but it made a short/error return
/// indistinguishable from an end-of-file boundary and offered no safe way to
/// retry a removable-volume I/O error. Positional reads let recovery reopen the
/// file at the precise digest offset. A short read is simply continued; only a
/// confirmed end at the statted size is accepted.
pub fn hashFileContentsWithProgressAndRecovery(
    io: std.Io,
    path: []const u8,
    progress: ?FileHashProgressFn,
    retry_observer: ?FileHashRetryFn,
    failure_observer: ?FileHashFailureFn,
) !u64 {
    return hashFileContentsWithProgressAndRecoveryWithOptions(
        io,
        path,
        progress,
        retry_observer,
        failure_observer,
        defaultFileHashOptions(),
    );
}

fn openInputFile(io: std.Io, path: []const u8) !std.Io.File {
    return if (std.fs.path.isAbsolute(path))
        std.Io.Dir.openFileAbsolute(io, path, .{})
    else
        std.Io.Dir.cwd().openFile(io, path, .{});
}

/// Bytes the filesystem has actually committed to the file.
///
/// `Stat` reports the length a file claims. It cannot distinguish an image
/// that was written whole from one whose tail was never stored, because both
/// carry the same size. The block count can, and that is the evidence which
/// separates a failing volume from an input that arrived truncated.
fn allocatedBytes(file: std.Io.File) ?u64 {
    var raw: std.c.Stat = undefined;
    if (std.c.fstat(file.handle, &raw) != 0) return null;
    if (raw.blocks < 0) return null;
    return @as(u64, @intCast(raw.blocks)) * 512;
}

/// Whether an error name describes a device that would not answer, as opposed
/// to a short file or a replaced one. The two recovery bounds are folded in:
/// both are only ever reached by way of a retryable read error, so both still
/// describe a refusal by the device.
fn isDeviceFaultName(error_name: []const u8) bool {
    const device_faults = [_][]const u8{
        "InputOutput",
        "SystemResources",
        "WouldBlock",
        "NoDevice",
        "InputRecoveryTimeout",
        "InputRecoveryLimitExceeded",
    };
    for (device_faults) |name| {
        if (std.mem.eql(u8, error_name, name)) return true;
    }
    return false;
}

fn classifyFaultOwner(error_name: []const u8, diagnosis: InputFaultDiagnosis) InputFaultOwner {
    if (std.mem.eql(u8, error_name, "InputChanged")) return .input_replaced;
    if (std.mem.eql(u8, error_name, "UnexpectedEndOfFile")) return .input_truncated;
    if (!isDeviceFaultName(error_name)) return .undetermined;
    // A device refused a region. Whether the image is the victim or the cause
    // turns on whether those bytes were ever stored in the first place.
    const fully_allocated = diagnosis.fullyAllocated() orelse return .undetermined;
    return if (fully_allocated) .host_media else .input_truncated;
}

/// One probe of one offset, with the survey's budget attached.
const DamageProbe = struct {
    io: std.Io,
    path: []const u8,
    buffer: []u8,
    options: FileHashOptions,
    started_ns: u64,
    survey: *InputDamageSurvey,

    fn exhausted(self: DamageProbe) bool {
        if (self.options.survey_max_probes != 0 and
            self.survey.probes_attempted >= self.options.survey_max_probes) return true;
        if (self.options.survey_max_time_ns != 0) {
            const now = monotonicNanoseconds();
            const elapsed = if (now > self.started_ns) now - self.started_ns else 0;
            if (elapsed >= self.options.survey_max_time_ns) return true;
        }
        return false;
    }

    /// `null` reports that the budget ran out. That is a different answer from
    /// "unreadable" and must never be recorded as one: a bounded probe that
    /// stopped early has not established anything about the offset.
    fn readable(self: DamageProbe, offset: u64) ?bool {
        if (self.exhausted()) return null;
        self.survey.probes_attempted += 1;
        // Reopen for each probe. A descriptor that has already taken a device
        // fault is not a clean instrument for deciding whether the next offset
        // is readable, and the recovery path already treats a reopen as the
        // way to clear that state.
        var file = openInputFile(self.io, self.path) catch return null;
        defer file.close(self.io);
        const count = file.readPositional(self.io, &.{self.buffer}, offset) catch {
            self.survey.probes_failed += 1;
            return false;
        };
        return count != 0;
    }
};

/// Establish where an unreadable region begins and ends, without paying the
/// device's stall once per block.
///
/// The two halves of the search are deliberately asymmetric, because the cost
/// of a probe is not symmetric: a readable offset answers immediately, while
/// an unreadable one first burns the device's whole internal retry budget.
/// Finding the first bad offset is therefore a forward walk, which pays that
/// stall exactly once. Finding where the damage ends is a gallop and a
/// bisection, which keeps the number of *failing* probes logarithmic in the
/// size of the hole. A linear walk of the far edge would pay tens of seconds
/// per block and would be indistinguishable from a hang.
fn surveyDamage(
    io: std.Io,
    path: []const u8,
    scan_start: u64,
    request_bytes: usize,
    total_bytes: ?u64,
    options: FileHashOptions,
) InputDamageSurvey {
    var probe_buffer: [64 * 1024]u8 = undefined;
    const probe_bytes = @max(@as(usize, 512), @min(probe_buffer.len, options.survey_probe_bytes));
    var survey = InputDamageSurvey{
        .scan_start = scan_start,
        .probe_bytes = probe_bytes,
    };
    const started_ns = monotonicNanoseconds();
    const probe = DamageProbe{
        .io = io,
        .path = path,
        .buffer = probe_buffer[0..probe_bytes],
        .options = options,
        .started_ns = started_ns,
        .survey = &survey,
    };

    // The tail first, as a single probe. It separates a localized hole from a
    // volume that has stopped answering past this point, and those are the
    // difference between recopying one file and not trusting the device.
    if (total_bytes) |total| {
        if (total > probe_bytes) survey.tail_readable = probe.readable(total - probe_bytes);
    }

    // Walk forward for the first offset that actually refuses. The failing
    // request covered a whole window and a single bad block anywhere inside it
    // is enough to fail the lot, so the digest offset is only where to start
    // looking.
    const scan_window: u64 = @max(@as(u64, probe_bytes), request_bytes);
    var scanned: u64 = 0;
    while (scanned < scan_window) : (scanned += probe_bytes) {
        const candidate = scan_start + scanned;
        if (total_bytes) |total| if (candidate >= total) break;
        const outcome = probe.readable(candidate) orelse {
            survey.budget_exhausted = true;
            break;
        };
        if (!outcome) {
            survey.first_fault_offset = candidate;
            break;
        }
    }

    const first_fault = survey.first_fault_offset orelse {
        const finished_transient_ns = monotonicNanoseconds();
        survey.elapsed_ns = if (finished_transient_ns > started_ns)
            finished_transient_ns - started_ns
        else
            0;
        return survey;
    };

    // Gallop to the first readable offset past the damage.
    var last_bad = first_fault;
    var first_good: ?u64 = null;
    var step: u64 = @max(@as(u64, probe_bytes), options.survey_gallop_start_bytes);
    while (step <= options.survey_window_bytes) : (step *= 2) {
        const candidate = first_fault + step;
        if (total_bytes) |total| if (candidate >= total) break;
        const outcome = probe.readable(candidate) orelse {
            survey.budget_exhausted = true;
            break;
        };
        if (outcome) {
            first_good = candidate;
            break;
        }
        last_bad = candidate;
    }

    // Bisect the boundary the gallop bracketed.
    if (first_good) |bracket| {
        var high = bracket;
        while (high - last_bad > probe_bytes) {
            const span = (high - last_bad) / 2;
            const aligned = span - (span % probe_bytes);
            if (aligned == 0) break;
            const middle = last_bad + aligned;
            const outcome = probe.readable(middle) orelse {
                survey.budget_exhausted = true;
                break;
            };
            if (outcome) high = middle else last_bad = middle;
        }
        survey.resume_offset = high;
    }

    const finished_ns = monotonicNanoseconds();
    survey.elapsed_ns = if (finished_ns > started_ns) finished_ns - started_ns else 0;
    return survey;
}

/// Carries a launch-input read failure to its observers.
///
/// The failure observer records the fact at once; the diagnosis observer is
/// allowed to spend real time first, because it only ever runs on a launch
/// that has already been refused.
const FaultReporter = struct {
    io: std.Io,
    path: []const u8,
    options: FileHashOptions,
    failure_observer: ?FileHashFailureFn,
    diagnosis_observer: ?FileHashDiagnosisFn,
    survey_start_observer: ?FileHashSurveyStartFn,
    total_bytes: ?u64,
    allocated_bytes: ?u64,

    fn report(
        self: FaultReporter,
        offset: u64,
        attempts: u32,
        chunk_bytes: usize,
        error_name: []const u8,
        wait_ns: u64,
    ) void {
        if (self.failure_observer) |observe| {
            observe(offset, self.total_bytes, attempts, chunk_bytes, error_name, wait_ns);
        }
        const observe_diagnosis = self.diagnosis_observer orelse return;
        var diagnosis = InputFaultDiagnosis{
            .offset = offset,
            .request_bytes = chunk_bytes,
            .error_name = error_name,
            .fault_wait_ns = wait_ns,
            .recovery_events = attempts,
            .logical_size = self.total_bytes,
            .allocated_bytes = self.allocated_bytes,
        };
        if (self.options.survey_damage and isDeviceFaultName(error_name)) {
            if (self.survey_start_observer) |announce| {
                announce(offset, self.options.survey_max_time_ns);
            }
            diagnosis.survey = surveyDamage(
                self.io,
                self.path,
                offset,
                chunk_bytes,
                self.total_bytes,
                self.options,
            );
        }
        diagnosis.owner = classifyFaultOwner(error_name, diagnosis);
        observe_diagnosis(diagnosis);
    }
};

pub fn hashFileContentsWithProgressAndRecoveryWithOptions(
    io: std.Io,
    path: []const u8,
    progress: ?FileHashProgressFn,
    retry_observer: ?FileHashRetryFn,
    failure_observer: ?FileHashFailureFn,
    options: FileHashOptions,
) !u64 {
    return hashFileContentsWithDiagnosis(
        io,
        path,
        progress,
        retry_observer,
        failure_observer,
        null,
        null,
        options,
    );
}

/// The full form. `diagnosis_observer` receives what the audit could establish
/// about an input it failed to hash: which side owns the fault, how long the
/// device took to refuse, and how far the unreadable region extends.
pub fn hashFileContentsWithDiagnosis(
    io: std.Io,
    path: []const u8,
    progress: ?FileHashProgressFn,
    retry_observer: ?FileHashRetryFn,
    failure_observer: ?FileHashFailureFn,
    diagnosis_observer: ?FileHashDiagnosisFn,
    survey_start_observer: ?FileHashSurveyStartFn,
    options: FileHashOptions,
) !u64 {
    var file: ?std.Io.File = try openInputFile(io, path);
    defer if (file) |opened| opened.close(io);

    var total_bytes: ?u64 = null;
    var initial_stat: ?std.Io.File.Stat = null;
    if (file.?.stat(io)) |stat| {
        if (stat.kind == .file) {
            total_bytes = stat.size;
            initial_stat = stat;
        }
    } else |_| {}
    const allocated_bytes = allocatedBytes(file.?);

    const faults = FaultReporter{
        .io = io,
        .path = path,
        .options = options,
        .failure_observer = failure_observer,
        .diagnosis_observer = diagnosis_observer,
        .survey_start_observer = survey_start_observer,
        .total_bytes = total_bytes,
        .allocated_bytes = allocated_bytes,
    };

    var buffer: [1024 * 1024]u8 = undefined;
    var digest = std.crypto.hash.sha2.Sha256.init(.{});
    const progress_interval: u64 = 256 * 1024 * 1024;
    const retry_limit = options.retry_limit;
    const retry_chunk_bytes = @min(buffer.len, options.retry_chunk_bytes);
    const final_retry_chunk_bytes = @min(buffer.len, options.final_retry_chunk_bytes);
    var next_progress = progress_interval;
    var bytes_read: u64 = 0;
    var last_reported_bytes: u64 = 0;
    var recovery_attempts: u32 = 0;
    var recovery_events: u32 = 0;
    var recovery_active = false;
    var recovery_clean_bytes: u64 = 0;
    var recovery_started_ns: u64 = 0;
    var recovery_chunk_bytes: usize = buffer.len;

    while (true) {
        if (total_bytes) |total| if (bytes_read >= total) break;
        // Once a device has faulted, stay in the smaller recovery mode until
        // a clean window has completed.  Resetting to a 1 MiB request after a
        // single 64 KiB success repeatedly re-enters the slow kernel/device
        // recovery path on every adjacent block of a damaged region.
        const max_read = recovery_chunk_bytes;
        const requested: usize = if (total_bytes) |total|
            @intCast(@min(total - bytes_read, @as(u64, max_read)))
        else
            max_read;

        // Timed on every read so a refusal can report how long it was waited
        // on. A device burning its own retry budget takes tens of seconds and
        // a filesystem-level refusal returns at once; the error name is the
        // same either way, and the duration is the only thing that separates
        // them in the retained log.
        const read_started_ns = monotonicNanoseconds();
        const count = file.?.readPositional(io, &.{buffer[0..requested]}, bytes_read) catch |err| {
            const error_name = @errorName(err);
            const now_ns = monotonicNanoseconds();
            const fault_wait_ns = if (now_ns > read_started_ns) now_ns - read_started_ns else 0;
            if (isRetryableFileReadError(err)) {
                if (!recovery_active) {
                    recovery_active = true;
                    recovery_clean_bytes = 0;
                    recovery_started_ns = now_ns;
                    recovery_chunk_bytes = if (retry_chunk_bytes != 0) retry_chunk_bytes else 1;
                }
                recovery_events += 1;
                recovery_attempts += 1;
                if (recovery_attempts >= 2 and final_retry_chunk_bytes != 0) {
                    recovery_chunk_bytes = final_retry_chunk_bytes;
                }
                const recovery_elapsed_ns = if (now_ns > recovery_started_ns)
                    now_ns - recovery_started_ns
                else
                    0;
                const recovery_failure: ?anyerror = if (options.max_recovery_events != 0 and
                    recovery_events >= options.max_recovery_events)
                    error.InputRecoveryLimitExceeded
                else if (options.max_recovery_time_ns != 0 and
                    recovery_elapsed_ns >= options.max_recovery_time_ns)
                    error.InputRecoveryTimeout
                else
                    null;
                if (recovery_failure) |failure| {
                    faults.report(
                        bytes_read,
                        recovery_events,
                        requested,
                        @errorName(failure),
                        fault_wait_ns,
                    );
                    return failure;
                }
                if (recovery_attempts <= retry_limit) {
                    if (retry_observer) |report| {
                        report(bytes_read, recovery_events, requested, error_name, fault_wait_ns);
                    }
                    file.?.close(io);
                    file = null;
                    file = openInputFile(io, path) catch |open_err| {
                        faults.report(
                            bytes_read,
                            recovery_events,
                            requested,
                            @errorName(open_err),
                            fault_wait_ns,
                        );
                        return open_err;
                    };
                    continue;
                }
            }
            faults.report(bytes_read, recovery_events, requested, error_name, fault_wait_ns);
            return err;
        };
        if (count == 0) {
            if (total_bytes) |total| {
                if (bytes_read < total) {
                    if (recovery_attempts <= retry_limit) {
                        const now_ns = monotonicNanoseconds();
                        if (!recovery_active) {
                            recovery_active = true;
                            recovery_clean_bytes = 0;
                            recovery_started_ns = now_ns;
                            recovery_chunk_bytes = if (retry_chunk_bytes != 0) retry_chunk_bytes else 1;
                        }
                        recovery_events += 1;
                        recovery_attempts += 1;
                        if (recovery_attempts >= 2 and final_retry_chunk_bytes != 0) {
                            recovery_chunk_bytes = final_retry_chunk_bytes;
                        }
                        const recovery_elapsed_ns = if (now_ns > recovery_started_ns)
                            now_ns - recovery_started_ns
                        else
                            0;
                        const recovery_failure: ?anyerror = if (options.max_recovery_events != 0 and
                            recovery_events >= options.max_recovery_events)
                            error.InputRecoveryLimitExceeded
                        else if (options.max_recovery_time_ns != 0 and
                            recovery_elapsed_ns >= options.max_recovery_time_ns)
                            error.InputRecoveryTimeout
                        else
                            null;
                        if (recovery_failure) |failure| {
                            faults.report(
                                bytes_read,
                                recovery_events,
                                requested,
                                @errorName(failure),
                                0,
                            );
                            return failure;
                        }
                        if (retry_observer) |report| {
                            report(bytes_read, recovery_events, requested, "UnexpectedEndOfFile", 0);
                        }
                        file.?.close(io);
                        file = null;
                        file = openInputFile(io, path) catch |open_err| {
                            faults.report(
                                bytes_read,
                                recovery_events,
                                requested,
                                @errorName(open_err),
                                0,
                            );
                            return open_err;
                        };
                        continue;
                    }
                    faults.report(
                        bytes_read,
                        recovery_events,
                        requested,
                        "UnexpectedEndOfFile",
                        0,
                    );
                    return error.UnexpectedEndOfFile;
                }
            }
            break;
        }
        digest.update(buffer[0..count]);
        bytes_read += count;
        recovery_attempts = 0;
        if (recovery_active) {
            recovery_clean_bytes += count;
            if (options.recovery_reset_bytes == 0 or recovery_clean_bytes >= options.recovery_reset_bytes) {
                recovery_active = false;
                recovery_clean_bytes = 0;
                recovery_started_ns = 0;
                recovery_events = 0;
                recovery_chunk_bytes = buffer.len;
            }
        }
        if (progress) |report| {
            if (bytes_read >= next_progress) {
                report(bytes_read, total_bytes);
                last_reported_bytes = bytes_read;
                next_progress = bytes_read + progress_interval;
            }
        }
    }

    if (total_bytes) |total| {
        if (bytes_read != total) {
            faults.report(bytes_read, recovery_events, buffer.len, "UnexpectedEndOfFile", 0);
            return error.UnexpectedEndOfFile;
        }
    }

    // The descriptor remains open throughout the hash, so a replacement or
    // resize cannot make the digest silently describe a different input.
    if (initial_stat) |before| {
        if (file.?.stat(io)) |after| {
            if (after.kind != .file or after.inode != before.inode or
                after.size != before.size or
                after.mtime.nanoseconds != before.mtime.nanoseconds or
                after.ctime.nanoseconds != before.ctime.nanoseconds)
            {
                faults.report(bytes_read, recovery_events, buffer.len, "InputChanged", 0);
                return error.InputChanged;
            }
        } else |err| {
            faults.report(bytes_read, recovery_events, buffer.len, @errorName(err), 0);
            return err;
        }
    }

    if (progress) |report| {
        if (bytes_read != last_reported_bytes) report(bytes_read, total_bytes);
    }

    const result = digest.finalResult();
    const hash = std.mem.readInt(u64, result[0..8], .big);
    return if (hash == 0) 1 else hash;
}

fn monotonicNanoseconds() u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(@as(std.c.clockid_t, .MONOTONIC), &timestamp) != 0) return 0;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

fn environmentUnsigned(name: [*:0]const u8, fallback: u64, maximum: u64) u64 {
    const raw = std.c.getenv(name) orelse return fallback;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    if (value.len == 0) return fallback;
    const parsed = std.fmt.parseUnsigned(u64, value, 10) catch return fallback;
    return @min(parsed, maximum);
}

fn isRetryableFileReadError(err: anyerror) bool {
    return switch (err) {
        error.InputOutput, error.SystemResources, error.WouldBlock, error.NoDevice => true,
        else => false,
    };
}

pub fn hashFromEnvironment(name: [*:0]const u8) u64 {
    const raw = std.c.getenv(name) orelse return 0;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    if (value.len == 0) return 0;
    // Deployment tooling may provide a numeric digest while source-control
    // tooling commonly provides a hexadecimal revision. Preserve a numeric
    // digest exactly. A path is not an identity: reject path-shaped values so
    // an operator cannot accidentally seal a run against the path string
    // rather than the verified bytes it names. The build-identity tool supplies
    // content digests for those inputs.
    if (std.fmt.parseUnsigned(u64, value, 0)) |parsed| {
        return parsed;
    } else |_| {
        if (std.mem.indexOfAny(u8, value, "/\\") != null or
            std.mem.startsWith(u8, value, "~") or
            std.mem.startsWith(u8, value, ".")) return 0;
        const hex = if (std.mem.startsWith(u8, value, "0x")) value[2..] else value;
        if (hex.len >= 16) {
            if (std.fmt.parseUnsigned(u64, hex[0..16], 16)) |parsed| return parsed else |_| {}
        }
        return hashIdentityBytes(value);
    }
}

pub fn firstHashFromEnvironment(primary: [*:0]const u8, alias: [*:0]const u8) u64 {
    const value = hashFromEnvironment(primary);
    return if (value != 0) value else hashFromEnvironment(alias);
}

fn configuredValueHash(primary: [*:0]const u8, alias: [*:0]const u8, label: []const u8) u64 {
    const supplied = hashFromEnvironment(primary);
    if (supplied != 0) return supplied;
    const raw = std.c.getenv(alias) orelse return 0;
    const value = std.mem.trim(u8, std.mem.span(raw), " \t\r\n");
    if (value.len == 0 or
        std.mem.indexOfAny(u8, value, "/\\") != null or
        std.mem.startsWith(u8, value, "~") or
        std.mem.startsWith(u8, value, ".")) return 0;
    return hashIdentityTag(label, value);
}

/// Capture the identity supplied by the build/deployment boundary. Missing
/// values stay zero deliberately: `Manifest.seal` treats them as a reason the
/// run is incomparable, rather than inventing an identity from a filename or
/// from the current process.
pub fn identityFieldsFromEnvironment() IdentityFields {
    return .{
        .rosette_source_revision = firstHashFromEnvironment("ROSETTE_SOURCE_REVISION_HASH", "ROSETTE_SOURCE_REVISION"),
        .rosette_tree_hash = firstHashFromEnvironment("ROSETTE_TREE_HASH", "ROSETTE_SOURCE_TREE_HASH"),
        .rosette_generated_tree_hash = firstHashFromEnvironment("ROSETTE_GENERATED_TREE_HASH", "ROSETTE_GENERATED_SOURCE_TREE_HASH"),
        .xenia_source_revision = firstHashFromEnvironment("XENIA_SOURCE_REVISION_HASH", "XENIA_SOURCE_REVISION"),
        .xenia_tree_hash = firstHashFromEnvironment("XENIA_TREE_HASH", "XENIA_SOURCE_TREE_HASH"),
        .xenia_base_commit_hash = firstHashFromEnvironment("XENIA_BASE_COMMIT_HASH", "XENIA_BASE_HASH"),
        .build_hash = firstHashFromEnvironment("ROSETTE_BUILD_HASH", "ROSETTE_GENERATION_HASH"),
        .toolchain_hash = firstHashFromEnvironment("ROSETTE_TOOLCHAIN_HASH", "ROSETTE_ZIG_HASH"),
        .host_hash = firstHashFromEnvironment("ROSETTE_HOST_HASH", "ROSETTE_HOST_IDENTITY_HASH"),
        .driver_hash = firstHashFromEnvironment("ROSETTE_DRIVER_HASH", "ROSETTE_GPU_DRIVER_HASH"),
        .generated_artifact_hash = firstHashFromEnvironment("ROSETTE_GENERATED_ARTIFACT_HASH", "ROSETTE_ARTIFACT_HASH"),
        .helper_hash = firstHashFromEnvironment("ROSETTE_HELPER_HASH", "ROSETTE_SHELL_HELPER_HASH"),
        .cvar_hash = firstHashFromEnvironment("ROSETTE_CVAR_HASH", "XENIA_CVAR_HASH"),
        .schema_hash = firstHashFromEnvironment("ROSETTE_SCHEMA_HASH", "XENIA_SCHEMA_HASH"),
        .test_runner_hash = firstHashFromEnvironment("ROSETTE_TEST_RUNNER_HASH", "ROSETTE_TEST_CENSUS_HASH"),
        .backend_hash = configuredValueHash("ROSETTE_BACKEND_HASH", "ROSETTE_BACKEND", "ROSETTE_BACKEND"),
        .device_hash = configuredValueHash("ROSETTE_DEVICE_HASH", "ROSETTE_DEVICE", "ROSETTE_DEVICE"),
        .moltenvk_hash = configuredValueHash("ROSETTE_MOLTENVK_HASH", "ROSETTE_MOLTENVK", "ROSETTE_MOLTENVK"),
        .metal_hash = configuredValueHash("ROSETTE_METAL_HASH", "ROSETTE_METAL_CAPABILITIES", "ROSETTE_METAL_CAPABILITIES"),
        .semantic_config_hash = firstHashFromEnvironment("ROSETTE_SEMANTIC_CONFIG_HASH", "ROSETTE_CONFIGURATION_HASH"),
        .time_config_hash = firstHashFromEnvironment("ROSETTE_TIME_CONFIG_HASH", "ROSETTE_TIME_CONFIG"),
        .scheduler_config_hash = firstHashFromEnvironment("ROSETTE_SCHEDULER_CONFIG_HASH", "ROSETTE_SCHEDULER_CONFIG"),
        .observer_config_hash = firstHashFromEnvironment("ROSETTE_OBSERVER_CONFIG_HASH", "ROSETTE_OBSERVER_CONFIG"),
        .admission_config_hash = firstHashFromEnvironment("ROSETTE_ADMISSION_CONFIG_HASH", "ROSETTE_ADMISSION_CONFIG"),
        .budget_config_hash = firstHashFromEnvironment("ROSETTE_BUDGET_CONFIG_HASH", "ROSETTE_BUDGET_CONFIG"),
        .frontier_config_hash = firstHashFromEnvironment("ROSETTE_FRONTIER_CONFIG_HASH", "ROSETTE_FRONTIER_CONFIG"),
        .shader_assets_hash = firstHashFromEnvironment("ROSETTE_SHADER_ASSETS_HASH", "ROSETTE_SHADER_ASSETS"),
        .vendor_hash = firstHashFromEnvironment("ROSETTE_VENDOR_HASH", "ROSETTE_VENDOR_LIBRARIES_HASH"),
        .fork_manifest_hash = firstHashFromEnvironment("ROSETTE_FORK_MANIFEST_HASH", "XENIA_FORK_MANIFEST_HASH"),
        .shell_update_hash = firstHashFromEnvironment("ROSETTE_SHELL_UPDATE_HASH", "ROSETTE_SHELL_UPDATE"),
        .entry_point_hash = hashFromEnvironment("ROSETTE_ENTRY_HASH"),
        .module_hash = hashFromEnvironment("ROSETTE_MODULE_HASH"),
        // These are part of this source-controlled ABI, not host guesses.
        .journal_schema = @import("durable_journal.zig").schema_version,
        .log_schema = bridge.contract.schema_version,
    };
}

/// Fill the two identities that Rosette can prove from the loaded bytes and
/// the resolved entry point. This does not fill build, host, driver, or Xenia
/// fields; those must still come from the deployment boundary.
pub fn identityFieldsWithImage(fields: IdentityFields, image_hash: u64, entry_point: u64) IdentityFields {
    var result = fields;
    if (result.module_hash == 0) result.module_hash = image_hash;
    if (result.entry_point_hash == 0) {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u64, bytes[0..8], image_hash, .little);
        std.mem.writeInt(u64, bytes[8..16], entry_point, .little);
        result.entry_point_hash = hashIdentityBytes(bytes[0..]);
    }
    if (result.schema_hash == 0) {
        result.schema_hash = hashIdentityTag("schema", build_identity_schema_value);
    }
    return result;
}

/// The mode a run declares about itself.
pub const Profile = enum(u8) {
    /// Nothing may fabricate guest progress, completion, publication, target
    /// content or a swap.
    authentic = 0,
    /// Interventions are permitted and the output is permanently labelled.
    diagnostic = 1,
    /// The harness stands in for the guest deliberately.
    synthetic = 2,
    /// A retained batch is replayed. Never a live guest run.
    replay = 3,

    pub fn label(self: Profile) []const u8 {
        return switch (self) {
            .authentic => "authentic",
            .diagnostic => "diagnostic",
            .synthetic => "synthetic",
            .replay => "replay",
        };
    }

    /// The strongest source class a frame from this run may claim.
    pub fn ceilingSourceClass(self: Profile) SourceClass {
        return switch (self) {
            .authentic => .guest_authentic,
            .diagnostic => .diagnostic,
            .synthetic => .synthetic,
            .replay => .replay,
        };
    }

    pub fn describe(self: Profile) []const u8 {
        return switch (self) {
            .authentic => "no intervention may fabricate guest progress. A frame from this run may be called the title's",
            .diagnostic => "interventions are permitted and every frame is permanently labelled non-authentic, however it looks",
            .synthetic => "the harness is standing in for the guest on purpose. Nothing this run produces describes the title",
            .replay => "a retained batch is being replayed against a model. This can prove two decoders agree and can never prove the guest executed anything",
        };
    }
};

/// Everything the run is measured against, declared before it starts.
pub const Budget = struct {
    /// The rate a graphics bring-up run has to hold, in guest milliseconds per
    /// host second.
    guest_ms_per_host_second: u64 = 0,
    /// The wall-clock window before the run is stopped.
    window_host_seconds: u64 = 0,
    /// The guest millisecond mark the run is trying to reach.
    guest_ms_target: u64 = 0,
};

/// A single input the run's identity depends on. Two runs with different
/// values here are not comparable, whatever else matches.
pub const Input = enum(u8) {
    image = 0,
    media = 1,
    config = 2,
    shader_cache = 3,

    pub fn label(self: Input) []const u8 {
        return switch (self) {
            .image => "image",
            .media => "media",
            .config => "config",
            .shader_cache => "shader-cache",
        };
    }
};

pub const input_count: usize = @typeInfo(Input).@"enum".fields.len;

/// Identity inputs that are not available from the title image alone. A zero
/// in any required slot means that the run is not comparable; it is never a
/// convenient default. Values are hashes supplied by the build/runtime
/// integration, so this structure is portable across hosts and can be copied
/// into the durable journal header without pointers.
pub const IdentityFields = struct {
    rosette_source_revision: u64 = 0,
    rosette_tree_hash: u64 = 0,
    rosette_generated_tree_hash: u64 = 0,
    xenia_source_revision: u64 = 0,
    xenia_tree_hash: u64 = 0,
    xenia_base_commit_hash: u64 = 0,
    build_hash: u64 = 0,
    toolchain_hash: u64 = 0,
    host_hash: u64 = 0,
    driver_hash: u64 = 0,
    generated_artifact_hash: u64 = 0,
    helper_hash: u64 = 0,
    cvar_hash: u64 = 0,
    schema_hash: u64 = 0,
    test_runner_hash: u64 = 0,
    backend_hash: u64 = 0,
    device_hash: u64 = 0,
    moltenvk_hash: u64 = 0,
    metal_hash: u64 = 0,
    semantic_config_hash: u64 = 0,
    time_config_hash: u64 = 0,
    scheduler_config_hash: u64 = 0,
    observer_config_hash: u64 = 0,
    admission_config_hash: u64 = 0,
    budget_config_hash: u64 = 0,
    frontier_config_hash: u64 = 0,
    shader_assets_hash: u64 = 0,
    vendor_hash: u64 = 0,
    fork_manifest_hash: u64 = 0,
    shell_update_hash: u64 = 0,
    entry_point_hash: u64 = 0,
    module_hash: u64 = 0,
    journal_schema: u16 = 0,
    log_schema: u16 = 0,

    pub fn complete(self: IdentityFields) bool {
        return self.rosette_source_revision != 0 and self.rosette_tree_hash != 0 and
            self.rosette_generated_tree_hash != 0 and
            self.xenia_source_revision != 0 and self.xenia_tree_hash != 0 and
            self.xenia_base_commit_hash != 0 and
            self.build_hash != 0 and self.toolchain_hash != 0 and
            self.host_hash != 0 and self.driver_hash != 0 and
            self.generated_artifact_hash != 0 and self.helper_hash != 0 and
            self.cvar_hash != 0 and self.schema_hash != 0 and
            self.test_runner_hash != 0 and self.backend_hash != 0 and
            self.device_hash != 0 and self.moltenvk_hash != 0 and
            self.metal_hash != 0 and self.semantic_config_hash != 0 and
            self.time_config_hash != 0 and self.scheduler_config_hash != 0 and
            self.observer_config_hash != 0 and self.admission_config_hash != 0 and
            self.budget_config_hash != 0 and self.frontier_config_hash != 0 and
            self.shader_assets_hash != 0 and self.vendor_hash != 0 and
            self.fork_manifest_hash != 0 and self.shell_update_hash != 0 and
            self.entry_point_hash != 0 and
            self.module_hash != 0 and self.journal_schema != 0 and self.log_schema != 0;
    }

    pub fn fingerprint(self: IdentityFields) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        const values = [_]u64{
            self.rosette_source_revision,
            self.rosette_tree_hash,
            self.rosette_generated_tree_hash,
            self.xenia_source_revision,
            self.xenia_tree_hash,
            self.xenia_base_commit_hash,
            self.build_hash,
            self.toolchain_hash,
            self.host_hash,
            self.driver_hash,
            self.generated_artifact_hash,
            self.helper_hash,
            self.cvar_hash,
            self.schema_hash,
            self.test_runner_hash,
            self.backend_hash,
            self.device_hash,
            self.moltenvk_hash,
            self.metal_hash,
            self.semantic_config_hash,
            self.time_config_hash,
            self.scheduler_config_hash,
            self.observer_config_hash,
            self.admission_config_hash,
            self.budget_config_hash,
            self.frontier_config_hash,
            self.shader_assets_hash,
            self.vendor_hash,
            self.fork_manifest_hash,
            self.shell_update_hash,
            self.entry_point_hash,
            self.module_hash,
            self.journal_schema,
            self.log_schema,
        };
        for (values) |value| hash = (hash ^ value) *% 0x100_0000_01b3;
        return hash;
    }
};

/// Stable names for the fields that may disagree at the build/runtime
/// boundary. Keeping this as an enum makes a conflict auditable without
/// serializing the whole identity record or guessing from the aggregate bool.
pub const IdentityField = enum(u8) {
    rosette_source_revision,
    rosette_tree_hash,
    rosette_generated_tree_hash,
    xenia_source_revision,
    xenia_tree_hash,
    xenia_base_commit_hash,
    build_hash,
    toolchain_hash,
    host_hash,
    driver_hash,
    generated_artifact_hash,
    helper_hash,
    cvar_hash,
    schema_hash,
    test_runner_hash,
    backend_hash,
    device_hash,
    moltenvk_hash,
    metal_hash,
    semantic_config_hash,
    time_config_hash,
    scheduler_config_hash,
    observer_config_hash,
    admission_config_hash,
    budget_config_hash,
    frontier_config_hash,
    shader_assets_hash,
    vendor_hash,
    fork_manifest_hash,
    shell_update_hash,
    entry_point_hash,
    module_hash,
    journal_schema,
    log_schema,
};

pub fn identityFieldLabel(field: IdentityField) []const u8 {
    return @tagName(field);
}

pub fn identityFieldValue(fields: IdentityFields, field: IdentityField) u64 {
    return switch (field) {
        .rosette_source_revision => fields.rosette_source_revision,
        .rosette_tree_hash => fields.rosette_tree_hash,
        .rosette_generated_tree_hash => fields.rosette_generated_tree_hash,
        .xenia_source_revision => fields.xenia_source_revision,
        .xenia_tree_hash => fields.xenia_tree_hash,
        .xenia_base_commit_hash => fields.xenia_base_commit_hash,
        .build_hash => fields.build_hash,
        .toolchain_hash => fields.toolchain_hash,
        .host_hash => fields.host_hash,
        .driver_hash => fields.driver_hash,
        .generated_artifact_hash => fields.generated_artifact_hash,
        .helper_hash => fields.helper_hash,
        .cvar_hash => fields.cvar_hash,
        .schema_hash => fields.schema_hash,
        .test_runner_hash => fields.test_runner_hash,
        .backend_hash => fields.backend_hash,
        .device_hash => fields.device_hash,
        .moltenvk_hash => fields.moltenvk_hash,
        .metal_hash => fields.metal_hash,
        .semantic_config_hash => fields.semantic_config_hash,
        .time_config_hash => fields.time_config_hash,
        .scheduler_config_hash => fields.scheduler_config_hash,
        .observer_config_hash => fields.observer_config_hash,
        .admission_config_hash => fields.admission_config_hash,
        .budget_config_hash => fields.budget_config_hash,
        .frontier_config_hash => fields.frontier_config_hash,
        .shader_assets_hash => fields.shader_assets_hash,
        .vendor_hash => fields.vendor_hash,
        .fork_manifest_hash => fields.fork_manifest_hash,
        .shell_update_hash => fields.shell_update_hash,
        .entry_point_hash => fields.entry_point_hash,
        .module_hash => fields.module_hash,
        .journal_schema => fields.journal_schema,
        .log_schema => fields.log_schema,
    };
}

/// Return one bit per field where both sources made a declaration and the
/// declarations disagree. A zero-valued field is absence, not a conflict.
pub fn identityConflictMask(supplied: IdentityFields, generated: IdentityFields) u64 {
    var mask: u64 = 0;
    inline for (@typeInfo(IdentityField).@"enum".fields) |field_info| {
        const field: IdentityField = @enumFromInt(field_info.value);
        const supplied_value = identityFieldValue(supplied, field);
        const generated_value = identityFieldValue(generated, field);
        if (supplied_value != 0 and generated_value != 0 and supplied_value != generated_value) {
            mask |= @as(u64, 1) << @intFromEnum(field);
        }
    }
    return mask;
}

/// The generated build-identity artifact is the deployment boundary for an
/// authentic run.  It deliberately contains more data than the compact
/// runtime identity, so the parser keeps only the content hashes needed by
/// the in-process manifest and never retains pointers into the JSON buffer.
const BuildIdentityValues = struct {
    rosette_source_revision: []const u8 = "",
    rosette_source_tree: []const u8 = "",
    rosette_generated_tree: []const u8 = "",
    media: []const u8 = "",
    xenia_source_revision: []const u8 = "",
    xenia_source_tree: []const u8 = "",
    xenia_fork_tree: []const u8 = "",
    xenia_base_commit: []const u8 = "",
    compiler: []const u8 = "",
    linker: []const u8 = "",
    translator: []const u8 = "",
    generator: []const u8 = "",
    shell_helper: []const u8 = "",
    build_graph: []const u8 = "",
    toolchain: []const u8 = "",
    host: []const u8 = "",
    backend: []const u8 = "",
    device: []const u8 = "",
    driver: []const u8 = "",
    moltenvk: []const u8 = "",
    metal: []const u8 = "",
    semantic_config: []const u8 = "",
    cvar: []const u8 = "",
    schema: []const u8 = "",
    time_config: []const u8 = "",
    scheduler_config: []const u8 = "",
    observer_config: []const u8 = "",
    admission_config: []const u8 = "",
    budget_config: []const u8 = "",
    frontier_config: []const u8 = "",
    shader_assets: []const u8 = "",
    vendor_libraries: []const u8 = "",
    test_manifest: []const u8 = "",
    shell_update: []const u8 = "",
};

const BuildIdentityDocument = struct {
    schema_version: u32 = 0,
    identity_hash: []const u8 = "",
    identity_hash_u64: []const u8 = "",
    identity: BuildIdentityValues = .{},
};

pub const BuildIdentity = struct {
    fields: IdentityFields,
    manifest_hash: u64,
    /// Optional selected-media identity from a manifest generated after the
    /// launch input was declared.  Most build artifacts are media-agnostic,
    /// so a zero here means the runtime must obtain the media from argv.
    media_hash: u64 = 0,
};

fn parseBuildDigest(text: []const u8) u64 {
    const value = std.mem.trim(u8, text, " \t\r\n");
    if (value.len == 0) return 0;
    const hex = if (std.mem.startsWith(u8, value, "0x")) value[2..] else value;
    if (hex.len == 0) return 0;
    const prefix = hex[0..@min(hex.len, @as(usize, 16))];
    return std.fmt.parseUnsigned(u64, prefix, 16) catch 0;
}

/// Parse the generated JSON and project its content-addressed identity into
/// the compact runtime record.  Unknown fields are ignored intentionally so
/// the generator may add explanatory inventory without changing the runtime
/// ABI; the schema and the two identity hash spellings remain mandatory.
pub fn parseBuildIdentityJson(allocator: std.mem.Allocator, bytes: []const u8) !BuildIdentity {
    const parsed = try std.json.parseFromSlice(
        BuildIdentityDocument,
        allocator,
        bytes,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    if (parsed.value.schema_version == 0) return error.MissingBuildIdentitySchema;
    if (parsed.value.schema_version != 2) return error.UnsupportedBuildIdentitySchema;

    const full_hash = parseBuildDigest(parsed.value.identity_hash);
    const short_hash = parseBuildDigest(parsed.value.identity_hash_u64);
    if (full_hash == 0 or short_hash == 0 or full_hash != short_hash) {
        return error.InvalidBuildIdentityHash;
    }

    const values = parsed.value.identity;
    const fields = IdentityFields{
        .rosette_source_revision = parseBuildDigest(values.rosette_source_revision),
        .rosette_tree_hash = parseBuildDigest(values.rosette_source_tree),
        .rosette_generated_tree_hash = parseBuildDigest(values.rosette_generated_tree),
        .xenia_source_revision = parseBuildDigest(values.xenia_source_revision),
        .xenia_tree_hash = parseBuildDigest(values.xenia_source_tree),
        .xenia_base_commit_hash = parseBuildDigest(values.xenia_base_commit),
        .build_hash = parseBuildDigest(values.build_graph),
        .toolchain_hash = parseBuildDigest(values.toolchain),
        .host_hash = parseBuildDigest(values.host),
        .driver_hash = parseBuildDigest(values.driver),
        .generated_artifact_hash = parseBuildDigest(values.generator),
        .helper_hash = parseBuildDigest(values.shell_helper),
        .cvar_hash = parseBuildDigest(values.cvar),
        .schema_hash = parseBuildDigest(values.schema),
        .test_runner_hash = parseBuildDigest(values.test_manifest),
        .backend_hash = parseBuildDigest(values.backend),
        .device_hash = parseBuildDigest(values.device),
        .moltenvk_hash = parseBuildDigest(values.moltenvk),
        .metal_hash = parseBuildDigest(values.metal),
        .semantic_config_hash = parseBuildDigest(values.semantic_config),
        .time_config_hash = parseBuildDigest(values.time_config),
        .scheduler_config_hash = parseBuildDigest(values.scheduler_config),
        .observer_config_hash = parseBuildDigest(values.observer_config),
        .admission_config_hash = parseBuildDigest(values.admission_config),
        .budget_config_hash = parseBuildDigest(values.budget_config),
        .frontier_config_hash = parseBuildDigest(values.frontier_config),
        .shader_assets_hash = parseBuildDigest(values.shader_assets),
        .vendor_hash = parseBuildDigest(values.vendor_libraries),
        .fork_manifest_hash = parseBuildDigest(values.xenia_fork_tree),
        .shell_update_hash = parseBuildDigest(values.shell_update),
        .journal_schema = @import("durable_journal.zig").schema_version,
        .log_schema = bridge.contract.schema_version,
    };
    return .{
        .fields = fields,
        .manifest_hash = full_hash,
        .media_hash = parseBuildDigest(values.media),
    };
}

fn mergeIdentityHash(generated: u64, supplied: u64, conflict: *bool) u64 {
    if (generated != 0 and supplied != 0 and generated != supplied) conflict.* = true;
    return if (generated != 0) generated else supplied;
}

/// Merge an authenticated generated identity with run-time values such as a
/// selected device or driver.  Generated values win; a disagreement is
/// reported rather than silently allowing environment state to replace the
/// admitted artifact.
pub fn mergeIdentityFields(supplied: IdentityFields, generated: IdentityFields, conflict: *bool) IdentityFields {
    var result = supplied;
    result.rosette_source_revision = mergeIdentityHash(generated.rosette_source_revision, supplied.rosette_source_revision, conflict);
    result.rosette_tree_hash = mergeIdentityHash(generated.rosette_tree_hash, supplied.rosette_tree_hash, conflict);
    result.rosette_generated_tree_hash = mergeIdentityHash(generated.rosette_generated_tree_hash, supplied.rosette_generated_tree_hash, conflict);
    result.xenia_source_revision = mergeIdentityHash(generated.xenia_source_revision, supplied.xenia_source_revision, conflict);
    result.xenia_tree_hash = mergeIdentityHash(generated.xenia_tree_hash, supplied.xenia_tree_hash, conflict);
    result.xenia_base_commit_hash = mergeIdentityHash(generated.xenia_base_commit_hash, supplied.xenia_base_commit_hash, conflict);
    result.build_hash = mergeIdentityHash(generated.build_hash, supplied.build_hash, conflict);
    result.toolchain_hash = mergeIdentityHash(generated.toolchain_hash, supplied.toolchain_hash, conflict);
    result.host_hash = mergeIdentityHash(generated.host_hash, supplied.host_hash, conflict);
    result.driver_hash = mergeIdentityHash(generated.driver_hash, supplied.driver_hash, conflict);
    result.generated_artifact_hash = mergeIdentityHash(generated.generated_artifact_hash, supplied.generated_artifact_hash, conflict);
    result.helper_hash = mergeIdentityHash(generated.helper_hash, supplied.helper_hash, conflict);
    result.cvar_hash = mergeIdentityHash(generated.cvar_hash, supplied.cvar_hash, conflict);
    result.schema_hash = mergeIdentityHash(generated.schema_hash, supplied.schema_hash, conflict);
    result.test_runner_hash = mergeIdentityHash(generated.test_runner_hash, supplied.test_runner_hash, conflict);
    result.backend_hash = mergeIdentityHash(generated.backend_hash, supplied.backend_hash, conflict);
    result.device_hash = mergeIdentityHash(generated.device_hash, supplied.device_hash, conflict);
    result.moltenvk_hash = mergeIdentityHash(generated.moltenvk_hash, supplied.moltenvk_hash, conflict);
    result.metal_hash = mergeIdentityHash(generated.metal_hash, supplied.metal_hash, conflict);
    result.semantic_config_hash = mergeIdentityHash(generated.semantic_config_hash, supplied.semantic_config_hash, conflict);
    result.time_config_hash = mergeIdentityHash(generated.time_config_hash, supplied.time_config_hash, conflict);
    result.scheduler_config_hash = mergeIdentityHash(generated.scheduler_config_hash, supplied.scheduler_config_hash, conflict);
    result.observer_config_hash = mergeIdentityHash(generated.observer_config_hash, supplied.observer_config_hash, conflict);
    result.admission_config_hash = mergeIdentityHash(generated.admission_config_hash, supplied.admission_config_hash, conflict);
    result.budget_config_hash = mergeIdentityHash(generated.budget_config_hash, supplied.budget_config_hash, conflict);
    result.frontier_config_hash = mergeIdentityHash(generated.frontier_config_hash, supplied.frontier_config_hash, conflict);
    result.shader_assets_hash = mergeIdentityHash(generated.shader_assets_hash, supplied.shader_assets_hash, conflict);
    result.vendor_hash = mergeIdentityHash(generated.vendor_hash, supplied.vendor_hash, conflict);
    result.fork_manifest_hash = mergeIdentityHash(generated.fork_manifest_hash, supplied.fork_manifest_hash, conflict);
    result.shell_update_hash = mergeIdentityHash(generated.shell_update_hash, supplied.shell_update_hash, conflict);
    result.entry_point_hash = mergeIdentityHash(generated.entry_point_hash, supplied.entry_point_hash, conflict);
    result.module_hash = mergeIdentityHash(generated.module_hash, supplied.module_hash, conflict);
    result.journal_schema = @intCast(mergeIdentityHash(generated.journal_schema, supplied.journal_schema, conflict));
    result.log_schema = @intCast(mergeIdentityHash(generated.log_schema, supplied.log_schema, conflict));
    return result;
}

/// Values that are only knowable for the process being launched.  The
/// generated build artifact owns source/build identity; this small runtime
/// portion owns the selected backend and the effective host/configuration
/// posture.  Empty values remain empty and therefore keep the authentic seal
/// fail-closed.
pub const RuntimeIdentityValues = struct {
    host: []const u8 = "",
    driver: []const u8 = "",
    cvar: []const u8 = "",
    backend: []const u8 = "",
    device: []const u8 = "",
    moltenvk: []const u8 = "",
    metal: []const u8 = "",
    semantic_config: []const u8 = "",
    time_config: []const u8 = "",
    scheduler_config: []const u8 = "",
    observer_config: []const u8 = "",
    admission_config: []const u8 = "",
    budget_config: []const u8 = "",
    frontier_config: []const u8 = "",
};

/// Complete only the runtime-owned fields that are still absent after the
/// generated manifest and explicit environment have been merged.  Generated
/// non-zero values always win, which preserves the conflict check above for a
/// stale or mismatched deployment artifact.
pub fn completeRuntimeIdentity(fields: IdentityFields, values: RuntimeIdentityValues) IdentityFields {
    var result = fields;
    if (result.host_hash == 0 and values.host.len != 0) result.host_hash = hashIdentityTag("host", values.host);
    if (result.driver_hash == 0 and values.driver.len != 0) result.driver_hash = hashIdentityTag("driver", values.driver);
    if (result.cvar_hash == 0 and values.cvar.len != 0) result.cvar_hash = hashIdentityTag("cvar", values.cvar);
    if (result.backend_hash == 0 and values.backend.len != 0) result.backend_hash = hashIdentityTag("backend", values.backend);
    if (result.device_hash == 0 and values.device.len != 0) result.device_hash = hashIdentityTag("device", values.device);
    if (result.moltenvk_hash == 0 and values.moltenvk.len != 0) result.moltenvk_hash = hashIdentityTag("moltenvk", values.moltenvk);
    if (result.metal_hash == 0 and values.metal.len != 0) result.metal_hash = hashIdentityTag("metal", values.metal);
    if (result.semantic_config_hash == 0 and values.semantic_config.len != 0) result.semantic_config_hash = hashIdentityTag("semantic-config", values.semantic_config);
    if (result.time_config_hash == 0 and values.time_config.len != 0) result.time_config_hash = hashIdentityTag("time-config", values.time_config);
    if (result.scheduler_config_hash == 0 and values.scheduler_config.len != 0) result.scheduler_config_hash = hashIdentityTag("scheduler-config", values.scheduler_config);
    if (result.observer_config_hash == 0 and values.observer_config.len != 0) result.observer_config_hash = hashIdentityTag("observer-config", values.observer_config);
    if (result.admission_config_hash == 0 and values.admission_config.len != 0) result.admission_config_hash = hashIdentityTag("admission-config", values.admission_config);
    if (result.budget_config_hash == 0 and values.budget_config.len != 0) result.budget_config_hash = hashIdentityTag("budget-config", values.budget_config);
    if (result.frontier_config_hash == 0 and values.frontier_config.len != 0) result.frontier_config_hash = hashIdentityTag("frontier-config", values.frontier_config);
    return result;
}

/// Why two runs cannot be compared.
pub const Comparability = enum(u8) {
    /// Same inputs, same profile. Differences are about the change under test.
    comparable,
    /// The inputs differ. A different frontier says nothing.
    inputs_differ,
    /// The profiles differ. One of them was allowed to fabricate.
    profiles_differ,
    /// One of them has not declared enough to compare.
    undeclared,

    pub fn label(self: Comparability) []const u8 {
        return switch (self) {
            .comparable => "comparable",
            .inputs_differ => "INPUTS-DIFFER",
            .profiles_differ => "PROFILES-DIFFER",
            .undeclared => "UNDECLARED",
        };
    }

    pub fn describe(self: Comparability) []const u8 {
        return switch (self) {
            .comparable => "the two runs used the same inputs under the same profile. A difference between them is about whatever changed between them",
            .inputs_differ => "the runs used different images, media, configuration or shader caches. A different frontier is not a finding — it is a different experiment",
            .profiles_differ => "the runs declared different profiles, so one of them was allowed to fabricate guest progress the other was not. Their frontiers are not measuring the same thing",
            .undeclared => "one of the runs has not stated its identity or its profile. Nothing can be concluded from putting them side by side",
        };
    }

    pub fn permitsComparison(self: Comparability) bool {
        return self == .comparable;
    }
};

pub const Manifest = struct {
    identity: RunIdentity = .{},
    profile: Profile = .authentic,
    /// Hashes for each identity input.
    inputs: [input_count]u64 = [_]u64{0} ** input_count,
    /// What this run's producers can emit. A reader uses it to tell "this
    /// producer does not emit resolves" from "this run had no resolves".
    features: FeatureSet = .{},
    budget: Budget = .{},
    /// Set once the manifest is complete. A run that never sealed its manifest
    /// cannot claim its own profile.
    sealed: bool = false,
    /// The frontier this run reached, for comparison with another.
    frontier_id: u64 = 0,
    /// Source/build/host identity beyond the title image itself.
    identity_fields: IdentityFields = .{},
    /// Set only by `seal`; later direct field mutation is detected by
    /// `sealIntact` and therefore cannot silently create a comparable run.
    seal_hash: u64 = 0,
    mutation_attempts: u64 = 0,

    pub fn declareInput(self: *Manifest, which: Input, hash: u64) bool {
        if (self.sealed) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.inputs[@intFromEnum(which)] = hash;
        return true;
    }

    pub fn inputHash(self: Manifest, which: Input) u64 {
        return self.inputs[@intFromEnum(which)];
    }

    pub fn declareFeature(self: *Manifest, feature: Feature) bool {
        if (self.sealed) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.features = self.features.with(feature);
        return true;
    }

    pub fn setIdentityFields(self: *Manifest, fields: IdentityFields) bool {
        if (self.sealed) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.identity_fields = fields;
        return true;
    }

    pub fn setBudget(self: *Manifest, budget: Budget) bool {
        if (self.sealed) {
            self.mutation_attempts +|= 1;
            return false;
        }
        self.budget = budget;
        return true;
    }

    /// Seal the manifest. Refuses when the identity is incomplete: a run that
    /// cannot say what it is cannot be compared to anything, and sealing it
    /// anyway would make that invisible.
    pub fn seal(self: *Manifest) bool {
        if (self.sealed) return self.sealIntact();
        if (!self.identity.valid()) return false;
        if (self.inputHash(.image) == 0 or self.inputHash(.media) == 0 or self.inputHash(.config) == 0) return false;
        if (!self.identity_fields.complete()) return false;
        self.seal_hash = self.computeFingerprint();
        self.sealed = true;
        return true;
    }

    pub fn sealIntact(self: *const Manifest) bool {
        return self.sealed and self.seal_hash != 0 and self.seal_hash == self.computeFingerprint();
    }

    /// The strongest class a frame may claim, given the profile and whatever
    /// the admission layer concluded. The lower of the two always wins.
    pub fn effectiveSourceClass(self: Manifest, admitted: SourceClass) SourceClass {
        const ceiling = self.profile.ceilingSourceClass();
        if (!self.sealIntact()) return .unknown;
        if (ceiling == .guest_authentic) return admitted;
        if (admitted == .guest_authentic) return ceiling;
        return if (admitted.taintsAuthenticity()) admitted else ceiling;
    }

    pub fn comparableWith(self: Manifest, other: Manifest) Comparability {
        if (!self.sealIntact() or !other.sealIntact()) return .undeclared;
        var index: usize = 0;
        while (index < input_count) : (index += 1) {
            if (self.inputs[index] != other.inputs[index]) return .inputs_differ;
        }
        if (self.profile != other.profile) return .profiles_differ;
        if (self.identity_fields.fingerprint() != other.identity_fields.fingerprint()) return .inputs_differ;
        return .comparable;
    }

    /// Whether two runs that are comparable reached the same frontier. This is
    /// the non-interference question: instrumentation on and off must land in
    /// the same place.
    pub fn sameFrontier(self: Manifest, other: Manifest) bool {
        if (!self.comparableWith(other).permitsComparison()) return false;
        return self.frontier_id != 0 and self.frontier_id == other.frontier_id;
    }

    pub fn fingerprint(self: Manifest) u64 {
        return self.computeFingerprint();
    }

    fn computeFingerprint(self: Manifest) u64 {
        var hash: u64 = self.identity.run_id;
        hash = hash *% 31 +% self.identity.image_hash;
        hash = hash *% 31 +% self.identity.media_hash;
        hash = hash *% 31 +% self.identity.title_id;
        for (self.inputs) |value| hash = hash *% 31 +% value;
        hash = hash *% 31 +% @intFromEnum(self.profile);
        hash = hash *% 31 +% self.features.bits;
        hash = hash *% 31 +% self.identity_fields.fingerprint();
        hash = hash *% 31 +% self.budget.guest_ms_per_host_second;
        hash = hash *% 31 +% self.budget.window_host_seconds;
        hash = hash *% 31 +% self.budget.guest_ms_target;
        return hash;
    }
};

fn sealedManifest(run_id: u64, profile: Profile) Manifest {
    var manifest = Manifest{
        .identity = .{ .run_id = run_id, .image_hash = 0x5ca5_bdca_5fd1_6245, .title_id = 0x4D53_07E6 },
        .profile = profile,
    };
    _ = manifest.declareInput(.image, 0x5ca5_bdca_5fd1_6245);
    _ = manifest.declareInput(.media, 0x8CEB_1ABA_7AC2_0BDA);
    _ = manifest.declareInput(.config, 0x1111);
    manifest.identity_fields = .{
        .rosette_source_revision = 1,
        .rosette_tree_hash = 2,
        .rosette_generated_tree_hash = 16,
        .xenia_source_revision = 3,
        .xenia_tree_hash = 4,
        .xenia_base_commit_hash = 17,
        .build_hash = 5,
        .toolchain_hash = 6,
        .host_hash = 7,
        .driver_hash = 8,
        .generated_artifact_hash = 9,
        .helper_hash = 10,
        .cvar_hash = 11,
        .schema_hash = 12,
        .test_runner_hash = 13,
        .backend_hash = 16,
        .device_hash = 17,
        .moltenvk_hash = 18,
        .metal_hash = 19,
        .semantic_config_hash = 20,
        .time_config_hash = 21,
        .scheduler_config_hash = 22,
        .observer_config_hash = 23,
        .admission_config_hash = 24,
        .budget_config_hash = 25,
        .frontier_config_hash = 26,
        .shader_assets_hash = 27,
        .vendor_hash = 28,
        .fork_manifest_hash = 29,
        .shell_update_hash = 30,
        .entry_point_hash = 14,
        .module_hash = 15,
        .journal_schema = 1,
        .log_schema = 1,
    };
    _ = manifest.seal();
    return manifest;
}

test "a manifest that cannot say what it is refuses to seal" {
    var manifest = Manifest{};
    try std.testing.expect(!manifest.seal());
    manifest.identity = .{ .run_id = 1 };
    try std.testing.expect(!manifest.seal());
    _ = manifest.declareInput(.image, 0xABCD);
    try std.testing.expect(!manifest.seal());
    try std.testing.expect(!manifest.sealed);
}

test "generated build identity is parsed and conflicts are fail-closed" {
    const text =
        \\{"schema_version":2,"identity_hash":"1111111111111111111111111111111111111111111111111111111111111111","identity_hash_u64":"1111111111111111","identity":{"rosette_source_revision":"2222222222222222222222222222222222222222222222222222222222222222"}}
    ;
    const generated = try parseBuildIdentityJson(std.testing.allocator, text);
    try std.testing.expectEqual(@as(u64, 0x1111_1111_1111_1111), generated.manifest_hash);
    try std.testing.expectEqual(@as(u64, 0x2222_2222_2222_2222), generated.fields.rosette_source_revision);

    var conflict = false;
    const merged = mergeIdentityFields(
        .{ .rosette_source_revision = 3 },
        generated.fields,
        &conflict,
    );
    try std.testing.expect(conflict);
    try std.testing.expectEqual(generated.fields.rosette_source_revision, merged.rosette_source_revision);

    const conflict_mask = identityConflictMask(
        .{ .rosette_source_revision = 3, .host_hash = 4 },
        .{ .rosette_source_revision = 0x2222, .host_hash = 4 },
    );
    try std.testing.expectEqual(@as(u64, 1), conflict_mask & 1);
    try std.testing.expectEqual(@as(u64, 0), conflict_mask & (@as(u64, 1) << 8));
}

test "an unsealed manifest cannot claim any source class" {
    var manifest = Manifest{ .profile = .authentic };
    try std.testing.expectEqual(SourceClass.unknown, manifest.effectiveSourceClass(.guest_authentic));
    manifest.identity = .{ .run_id = 1 };
    _ = manifest.declareInput(.image, 1);
    _ = manifest.seal();
    try std.testing.expectEqual(SourceClass.unknown, manifest.effectiveSourceClass(.guest_authentic));
}

test "the profile caps what a frame may claim and never raises it" {
    const authentic = sealedManifest(1, .authentic);
    try std.testing.expectEqual(SourceClass.guest_authentic, authentic.effectiveSourceClass(.guest_authentic));
    try std.testing.expectEqual(SourceClass.diagnostic, authentic.effectiveSourceClass(.diagnostic));

    // A diagnostic run cannot produce an authentic frame however clean the
    // admission layer thinks it is.
    const diagnostic = sealedManifest(2, .diagnostic);
    try std.testing.expectEqual(SourceClass.diagnostic, diagnostic.effectiveSourceClass(.guest_authentic));
    // And a synthetic admission still taints a diagnostic run.
    try std.testing.expectEqual(SourceClass.synthetic, diagnostic.effectiveSourceClass(.synthetic));
    try std.testing.expectEqual(SourceClass.replay, (sealedManifest(3, .replay)).effectiveSourceClass(.guest_authentic));
}

test "two runs of different images are a different experiment, not a finding" {
    var first = sealedManifest(1, .authentic);
    var second = sealedManifest(2, .authentic);
    try std.testing.expectEqual(Comparability.comparable, first.comparableWith(second));

    try std.testing.expect(!second.declareInput(.image, 0xDEAD));
    const verdict = first.comparableWith(second);
    try std.testing.expectEqual(Comparability.comparable, verdict);
    try std.testing.expect(verdict.permitsComparison());

    var different = sealedManifest(3, .authentic);
    // Build a different sealed identity before sealing it, rather than trying
    // to mutate a sealed manifest after the fact.
    different.sealed = false;
    different.seal_hash = 0;
    try std.testing.expect(different.declareInput(.image, 0xDEAD));
    try std.testing.expect(different.seal());
    const different_verdict = first.comparableWith(different);
    try std.testing.expectEqual(Comparability.inputs_differ, different_verdict);
    try std.testing.expect(!different_verdict.permitsComparison());
    try std.testing.expect(std.mem.indexOf(u8, different_verdict.describe(), "different experiment") != null);
}

test "two runs of different profiles are not measuring the same thing" {
    const authentic = sealedManifest(1, .authentic);
    const diagnostic = sealedManifest(2, .diagnostic);
    try std.testing.expectEqual(Comparability.profiles_differ, authentic.comparableWith(diagnostic));
    try std.testing.expect(!authentic.sameFrontier(diagnostic));
}

test "an unsealed run cannot be compared to anything" {
    const sealed = sealedManifest(1, .authentic);
    const unsealed = Manifest{};
    try std.testing.expectEqual(Comparability.undeclared, sealed.comparableWith(unsealed));
    try std.testing.expectEqual(Comparability.undeclared, unsealed.comparableWith(sealed));
}

// The audit's non-interference gate: instrumentation on and off must reach the
// same frontier before the instrumentation can be called safe.
test "the same frontier is only meaningful between comparable runs" {
    var instrumented = sealedManifest(1, .authentic);
    var quiet = sealedManifest(2, .authentic);
    instrumented.frontier_id = 7;
    quiet.frontier_id = 7;
    try std.testing.expect(instrumented.sameFrontier(quiet));

    quiet.frontier_id = 8;
    try std.testing.expect(!instrumented.sameFrontier(quiet));

    // An unknown frontier is never evidence of agreement.
    quiet.frontier_id = 0;
    instrumented.frontier_id = 0;
    try std.testing.expect(!instrumented.sameFrontier(quiet));
}

test "declared features separate a silent producer from an empty run" {
    var manifest = sealedManifest(1, .authentic);
    manifest.sealed = false;
    manifest.seal_hash = 0;
    try std.testing.expect(manifest.declareFeature(.resolve));
    try std.testing.expect(manifest.declareFeature(.frame_custody));
    try std.testing.expect(manifest.seal());
    try std.testing.expect(manifest.features.has(.resolve));
    // The sealed collection is immutable; the feature declarations above are
    // intentionally staged before the final seal.
    try std.testing.expect(!manifest.declareFeature(.resolve));
    try std.testing.expect(!manifest.declareFeature(.frame_custody));
    try std.testing.expect(manifest.features.has(.resolve));
    try std.testing.expectEqual(@as(usize, 2), manifest.features.count());
}

test "every profile, input and comparability states its own vocabulary" {
    inline for (@typeInfo(Profile).@"enum".fields) |field| {
        const which: Profile = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
    inline for (@typeInfo(Input).@"enum".fields) |field| {
        const which: Input = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
    }
    inline for (@typeInfo(Comparability).@"enum".fields) |field| {
        const which: Comparability = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
}

test "a device refusal on a fully stored file accuses the volume, not the image" {
    const diagnosis = InputFaultDiagnosis{
        .error_name = "InputOutput",
        .logical_size = 6_110_191_616,
        .allocated_bytes = 6_110_191_616,
    };
    try std.testing.expect(diagnosis.fullyAllocated().?);
    try std.testing.expectEqual(
        InputFaultOwner.host_media,
        classifyFaultOwner("InputOutput", diagnosis),
    );
    // The recovery bounds are reached only by way of a device refusal, so they
    // have to reach the same verdict as the refusal that produced them.
    try std.testing.expectEqual(
        InputFaultOwner.host_media,
        classifyFaultOwner("InputRecoveryTimeout", diagnosis),
    );
    try std.testing.expectEqual(
        InputFaultOwner.host_media,
        classifyFaultOwner("InputRecoveryLimitExceeded", diagnosis),
    );
}

test "a device refusal on a partly stored file accuses the image" {
    const diagnosis = InputFaultDiagnosis{
        .error_name = "InputOutput",
        .logical_size = 6_110_191_616,
        .allocated_bytes = 4_563_402_752,
    };
    try std.testing.expect(!diagnosis.fullyAllocated().?);
    try std.testing.expectEqual(
        InputFaultOwner.input_truncated,
        classifyFaultOwner("InputOutput", diagnosis),
    );
}

test "without a block count a device refusal names no owner" {
    const diagnosis = InputFaultDiagnosis{
        .error_name = "InputOutput",
        .logical_size = 6_110_191_616,
        .allocated_bytes = null,
    };
    try std.testing.expectEqual(@as(?bool, null), diagnosis.fullyAllocated());
    try std.testing.expectEqual(
        InputFaultOwner.undetermined,
        classifyFaultOwner("InputOutput", diagnosis),
    );
}

test "a short read and a replaced file are owned by the input whatever the volume did" {
    const stored = InputFaultDiagnosis{
        .logical_size = 1024,
        .allocated_bytes = 1024,
    };
    try std.testing.expectEqual(
        InputFaultOwner.input_truncated,
        classifyFaultOwner("UnexpectedEndOfFile", stored),
    );
    try std.testing.expectEqual(
        InputFaultOwner.input_replaced,
        classifyFaultOwner("InputChanged", stored),
    );
    try std.testing.expectEqual(
        InputFaultOwner.undetermined,
        classifyFaultOwner("AccessDenied", stored),
    );
}

test "only a device refusal is worth surveying" {
    try std.testing.expect(isDeviceFaultName("InputOutput"));
    try std.testing.expect(isDeviceFaultName("NoDevice"));
    try std.testing.expect(isDeviceFaultName("InputRecoveryTimeout"));
    try std.testing.expect(!isDeviceFaultName("UnexpectedEndOfFile"));
    try std.testing.expect(!isDeviceFaultName("InputChanged"));
}

test "a survey reports an extent only where it found both edges" {
    const measured = InputDamageSurvey{
        .scan_start = 4_744_806_400,
        .first_fault_offset = 4_744_806_400,
        .resume_offset = 4_745_347_072,
    };
    try std.testing.expectEqual(@as(?u64, 540_672), measured.damagedBytes());

    // A probe that ran out of budget never found the far edge. Reporting the
    // window it managed to cover as though it were the damage would understate
    // the fault, so it reports nothing at all.
    const bounded = InputDamageSurvey{
        .scan_start = 4_744_806_400,
        .first_fault_offset = 4_744_806_400,
        .resume_offset = null,
        .budget_exhausted = true,
    };
    try std.testing.expectEqual(@as(?u64, null), bounded.damagedBytes());

    // A window that re-read cleanly has no damage to size: the refusal that
    // started the survey was transient.
    const transient = InputDamageSurvey{ .scan_start = 4_744_806_400 };
    try std.testing.expectEqual(@as(?u64, null), transient.damagedBytes());
}

test "the block count reports what the volume actually stored" {
    const path = "/tmp/rosette-run-manifest-allocation-probe";
    const fd = std.c.open(path, .{ .ACCMODE = .RDWR, .CREAT = true, .TRUNC = true }, @as(std.c.mode_t, 0o600));
    try std.testing.expect(fd >= 0);
    defer _ = std.c.unlink(path);
    defer _ = std.c.close(fd);

    const payload = [_]u8{0xA5} ** 8192;
    try std.testing.expect(std.c.write(fd, &payload, payload.len) == payload.len);

    const file = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } };
    const allocated = allocatedBytes(file) orelse return error.AllocationUnavailable;
    try std.testing.expect(allocated >= payload.len);
}

test "every fault owner states its own vocabulary" {
    try std.testing.expectEqualStrings("host-media", InputFaultOwner.host_media.text());
    try std.testing.expectEqualStrings("input-truncated", InputFaultOwner.input_truncated.text());
    try std.testing.expectEqualStrings("input-replaced", InputFaultOwner.input_replaced.text());
    try std.testing.expectEqualStrings("undetermined", InputFaultOwner.undetermined.text());
}
