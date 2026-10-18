//! Reusable rules for publishing small snapshots between host threads.

pub const SnapshotPolicy = struct {
    atomic_bytes: u32,
    atomic_alignment: u32,
    producer_rate_hz: u32,

    pub fn canPublish(self: SnapshotPolicy, bytes: u32) bool {
        return self.atomic_bytes != 0 and bytes != 0 and bytes <= self.atomic_bytes;
    }

    pub fn isAligned(self: SnapshotPolicy, address: u64) bool {
        return self.atomic_alignment != 0 and address % self.atomic_alignment == 0;
    }

    pub fn coversConsumerRate(self: SnapshotPolicy, consumer_rate_hz: u32) bool {
        return consumer_rate_hz != 0 and self.producer_rate_hz > consumer_rate_hz;
    }
};
