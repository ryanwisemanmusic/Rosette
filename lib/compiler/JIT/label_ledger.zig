//! Mutable label state for a live host code-generation session.
//!
//! Label capacity and the rel32 limits are package facts. References and
//! definitions are effects of the current JIT buffer and therefore belong to
//! the runtime library.

const codegen = @import("xenia_codegen_activation");

pub const max_labels = codegen.max_labels;
pub const LabelId = codegen.LabelId;

pub const LabelState = struct {
    defined: bool = false,
    references: u32 = 0,
    address: u64 = 0,
};

pub const CodegenStatus = enum {
    ready,
    undefined_label,
    duplicate_label,
    invalid_reference,
};

pub const LabelLedger = struct {
    labels: [max_labels]LabelState = [_]LabelState{.{}} ** max_labels,
    label_count: u16 = 0,
    duplicate: bool = false,
    invalid: bool = false,

    pub fn reference(self: *LabelLedger, id: LabelId) bool {
        if (id >= max_labels) {
            self.invalid = true;
            return false;
        }
        self.labels[id].references +|= 1;
        self.label_count = @max(self.label_count, id + 1);
        return true;
    }

    pub fn define(self: *LabelLedger, id: LabelId, address: u64) bool {
        if (id >= max_labels) {
            self.invalid = true;
            return false;
        }
        if (self.labels[id].defined) {
            self.duplicate = true;
            return false;
        }
        self.labels[id].defined = true;
        self.labels[id].address = address;
        self.label_count = @max(self.label_count, id + 1);
        return true;
    }

    pub fn validate(self: *const LabelLedger) CodegenStatus {
        if (self.invalid) return .invalid_reference;
        if (self.duplicate) return .duplicate_label;
        for (self.labels[0..self.label_count]) |label| {
            if (label.references != 0 and !label.defined) return .undefined_label;
        }
        return .ready;
    }
};

test "runtime labels are undefined until the live buffer defines them" {
    var ledger = LabelLedger{};
    try @import("std").testing.expect(ledger.reference(11));
    try @import("std").testing.expectEqual(CodegenStatus.undefined_label, ledger.validate());
    try @import("std").testing.expect(ledger.define(11, 0x1000));
    try @import("std").testing.expectEqual(CodegenStatus.ready, ledger.validate());
}

test "runtime label state rejects duplicates and invalid references" {
    var ledger = LabelLedger{};
    try @import("std").testing.expect(ledger.define(3, 0x2000));
    try @import("std").testing.expect(!ledger.define(3, 0x3000));
    try @import("std").testing.expectEqual(CodegenStatus.duplicate_label, ledger.validate());

    var invalid = LabelLedger{};
    try @import("std").testing.expect(!invalid.reference(max_labels));
    try @import("std").testing.expectEqual(CodegenStatus.invalid_reference, invalid.validate());
}
